"""Granite Peak CRE Portfolio Intelligence: Databricks App.

Reads operational data from Lakebase (Postgres), writes analyst corrections back to Lakebase, serves lease PDFs
from the Unity Catalog volume, and answers questions through the Genie Conversation API on behalf of the
signed-in user, so Unity Catalog row filters apply to each user's own entitlements.
"""
import os
import time
import uuid

import pandas as pd
import psycopg
import pydeck as pdk
import streamlit as st
from databricks.sdk import WorkspaceClient

CATALOG = os.getenv("GRANITE_CATALOG", "smmorgan_catalog")
SCHEMA = os.getenv("GRANITE_SCHEMA", "granite_commercial_real_estate")
INSTANCE = os.getenv("LAKEBASE_INSTANCE", "granite-cre")
PG_DB = os.getenv("PGDATABASE", "databricks_postgres")
GENIE_SPACE_ID = os.getenv("GENIE_SPACE_ID", "")
REVIEWABLE_FIELDS = ["lease_end", "monthly_rent", "tenant_name", "renewal_option_count",
                     "has_co_tenancy", "has_termination_right", "termination_right_date"]

st.set_page_config(page_title="Granite Peak Portfolio Intelligence", layout="wide")


@st.cache_resource
def app_client():
    return WorkspaceClient()


def user_client():
    """Workspace client acting as the signed-in user (on-behalf-of auth), or the app if unavailable."""
    token = st.context.headers.get("x-forwarded-access-token")
    if token:
        return WorkspaceClient(host=app_client().config.host, token=token, auth_type="pat")
    return app_client()


@st.cache_resource
def _instance():
    return app_client().database.get_database_instance(INSTANCE)


def pg():
    w = app_client()
    cred = w.database.generate_database_credential(request_id=str(uuid.uuid4()), instance_names=[INSTANCE])
    user = os.getenv("PGUSER") or w.current_user.me().user_name
    return psycopg.connect(host=os.getenv("PGHOST") or _instance().read_write_dns, dbname=PG_DB, user=user,
                           password=cred.token, sslmode="require", autocommit=True)


@st.cache_data(ttl=300)
def query(sql, params=None):
    with pg() as conn:
        cur = conn.execute(sql, params or ())
        return pd.DataFrame(cur.fetchall(), columns=[d.name for d in cur.description])


def t(name):
    return f'"{SCHEMA}"."{name}_synced"'


st.title("Granite Peak Portfolio Intelligence")
st.caption("Lease documents, ERP rent roll and H3 market context on one governed platform. Synthetic data.")

tab_map, tab_prop, tab_review, tab_genie = st.tabs(["Portfolio map", "Property 360", "Lease review", "Ask Genie"])

# ── Portfolio map ───────────────────────────────────────────────────────────────
with tab_map:
    props = query(f"SELECT * FROM {t('property_360')}")
    props["h3"] = props["h3_res9"].map(lambda v: format(int(v), "x"))
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Properties", f"{len(props):,}")
    c2.metric("Annualized base rent", f"${props.abr.sum() / 1e6:,.1f}M")
    c3.metric("Occupancy", f"{(props.occupancy_rate * props.total_sqft).sum() / props.total_sqft.sum():.1%}")
    c4.metric("ABR expiring ≤ 24 months",
              f"{(props.pct_abr_expiring_24m.fillna(0) * props.abr).sum() / props.abr.sum():.1%}")
    msa = st.selectbox("Market", ["All"] + sorted(props.msa.unique()))
    color_by = st.radio("Color hexes by", ["% ABR expiring ≤ 24 months", "Competitor density (~1 km)"], horizontal=True)
    view = props if msa == "All" else props[props.msa == msa]
    metric = view.pct_abr_expiring_24m.fillna(0) if color_by.startswith("%") else \
        view.competitor_count.fillna(0) / max(view.competitor_count.max(), 1)
    view = view.assign(red=(metric.clip(0, 1) * 255).astype(int), elevation=(view.abr / 1e4))
    st.pydeck_chart(pdk.Deck(
        map_style=None,
        initial_view_state=pdk.ViewState(latitude=view.lat.mean(), longitude=view.lon.mean(),
                                         zoom=5 if msa == "All" else 10, pitch=40),
        layers=[pdk.Layer("H3HexagonLayer", view, get_hexagon="h3", get_fill_color="[red, 90, 160, 200]",
                          extruded=True, get_elevation="elevation", elevation_scale=20, pickable=True)],
        tooltip={"text": "{property_name}\n{property_type} · {msa}\nOccupancy {occupancy_rate}\nCompetitors ~1 km: {competitor_count}"},
    ))
    st.dataframe(view[["property_id", "property_name", "property_type", "msa", "neighborhood", "occupancy_rate",
                       "abr", "walt_years", "pct_abr_expiring_24m", "competitor_count"]]
                 .sort_values("pct_abr_expiring_24m", ascending=False), hide_index=True, use_container_width=True)

# ── Property 360 ────────────────────────────────────────────────────────────────
with tab_prop:
    props = query(f"SELECT property_id, property_name FROM {t('property_360')} ORDER BY property_id")
    choice = st.selectbox("Property", props.property_id + " · " + props.property_name)
    pid = choice.split(" · ")[0]
    t0 = time.perf_counter()
    p = query(f"SELECT * FROM {t('property_360')} WHERE property_id = %s", (pid,)).iloc[0]
    st.caption(f"Lakebase lookup: {(time.perf_counter() - t0) * 1000:.0f} ms")
    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("Occupancy", f"{p.occupancy_rate:.1%}")
    c2.metric("ABR", f"${p.abr:,.0f}")
    c3.metric("WALT", f"{(p.walt_years or 0):.1f} yrs")
    c4.metric("Competitors ~1 km", int(p.competitor_count or 0))
    c5.metric("Neighborhood", p.neighborhood or p.locality or "—")
    leases = query(f"""
        SELECT r.lease_id, r.tenant_name, r.lease_end, r.annual_base_rent, r.renewal_probability,
               r.expected_vacancy_loss, a.renewal_option_count, a.has_co_tenancy, a.has_termination_right,
               a.review_status
        FROM {t('renewal_scores')} r LEFT JOIN {t('lease_abstract')} a USING (lease_id)
        WHERE r.property_id = %s ORDER BY r.lease_end""", (pid,))
    st.subheader("Leases, renewal risk and document clauses")
    st.dataframe(leases, hide_index=True, use_container_width=True)

# ── Lease review ────────────────────────────────────────────────────────────────
with tab_review:
    st.subheader("Abstracts to review")
    st.caption("Leases whose extracted terms disagree with the ERP or are incomplete. Corrections are saved to "
               "Lakebase and flow back to the gold layer and Genie on the next pipeline update.")
    queue = query(f"""
        SELECT a.lease_id, a.tenant_name, a.review_status, a.abstract_confidence,
               d.erp_lease_end, d.abstract_lease_end, d.erp_monthly_rent, d.abstract_monthly_rent, a.path
        FROM {t('lease_abstract')} a LEFT JOIN {t('lease_discrepancies')} d USING (lease_id)
        WHERE d.lease_id IS NOT NULL OR a.review_status = 'needs_review'
        ORDER BY a.abstract_confidence, a.lease_id""")
    st.dataframe(queue.drop(columns=["path"]), hide_index=True, use_container_width=True)
    if not queue.empty:
        lease_id = st.selectbox("Lease", queue.lease_id)
        row = queue[queue.lease_id == lease_id].iloc[0]
        pdf_path = row.path.replace("dbfs:", "")
        if st.button("Load source PDF"):
            pdf = app_client().files.download(pdf_path).contents.read()
            st.download_button("Download lease PDF", pdf, file_name=f"{lease_id}.pdf", mime="application/pdf")
        with st.form("correction"):
            field = st.selectbox("Field", REVIEWABLE_FIELDS)
            current = query(f"SELECT {field}::text AS v FROM {t('lease_abstract')} WHERE lease_id = %s",
                            (lease_id,)).v.iloc[0]
            st.text(f"Extracted value: {current}")
            corrected = st.text_input("Confirmed value")
            if st.form_submit_button("Approve correction") and corrected:
                reviewer = st.context.headers.get("x-forwarded-email", "app")
                with pg() as conn:
                    conn.execute("""
                        INSERT INTO app.abstract_review (lease_id, field_name, extracted_value, corrected_value, status, reviewer)
                        VALUES (%s, %s, %s, %s, 'approved', %s)
                        ON CONFLICT (lease_id, field_name) DO UPDATE
                        SET corrected_value = EXCLUDED.corrected_value, reviewer = EXCLUDED.reviewer,
                            status = 'approved', reviewed_at = now()""",
                                 (lease_id, field, current, corrected, reviewer))
                st.success(f"Saved: {lease_id}.{field} = {corrected}")
    st.subheader("Recent corrections")
    st.dataframe(query("SELECT * FROM app.abstract_review ORDER BY reviewed_at DESC LIMIT 20"),
                 hide_index=True, use_container_width=True)

# ── Ask Genie ───────────────────────────────────────────────────────────────────
with tab_genie:
    st.subheader("Ask Genie")
    st.caption("Runs as you: answers only include the funds you are entitled to.")
    if not GENIE_SPACE_ID:
        st.warning("GENIE_SPACE_ID is not configured.")
    else:
        samples = ["Which held assets have more than 20% of rent rolling in the next 24 months?",
                   "Which retail assets have more than 25% of ABR expiring within 24 months and a co-tenancy clause?",
                   "For deal GP-ACQ-014, which held assets are within about 2 km, and what's their occupancy?"]
        question = st.text_input("Question", value=st.session_state.get("q", ""), placeholder=samples[0])
        cols = st.columns(len(samples))
        for c, s in zip(cols, samples):
            if c.button(s[:48] + "…", key=s):
                question = s
        if question:
            w = user_client()
            conv_id = st.session_state.get("conversation_id")
            with st.spinner("Genie is working..."):
                msg = (w.genie.create_message_and_wait(GENIE_SPACE_ID, conv_id, question) if conv_id
                       else w.genie.start_conversation_and_wait(GENIE_SPACE_ID, question))
            st.session_state["conversation_id"] = msg.conversation_id
            for att in msg.attachments or []:
                if att.text:
                    st.markdown(att.text.content)
                if att.query:
                    st.caption(att.query.description or "")
                    with st.expander("SQL"):
                        st.code(att.query.query, language="sql")
                    res = w.genie.get_message_attachment_query_result(GENIE_SPACE_ID, msg.conversation_id,
                                                                      msg.message_id, att.attachment_id)
                    sr = res.statement_response
                    cols_ = [c.name for c in sr.manifest.schema.columns]
                    st.dataframe(pd.DataFrame(sr.result.data_array or [], columns=cols_),
                                 hide_index=True, use_container_width=True)
        if st.button("New conversation"):
            st.session_state.pop("conversation_id", None)
