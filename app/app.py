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


PCT = st.column_config.NumberColumn(format="percent")
USD = st.column_config.NumberColumn(format="dollar")
COLS = {"occupancy_rate": PCT, "pct_abr_expiring_24m": PCT, "renewal_probability": PCT, "abstract_confidence": PCT,
        "abr": USD, "annual_base_rent": USD, "expected_vacancy_loss": USD,
        "erp_monthly_rent": USD, "abstract_monthly_rent": USD,
        "walt_years": st.column_config.NumberColumn(format="%.1f")}


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
    markets = sorted(props.msa.unique())
    msa = st.selectbox("Market", ["All"] + markets, index=1 + markets.index("Albuquerque") if "Albuquerque" in markets else 0)
    color_by = st.radio("Color by", ["% ABR expiring ≤ 24 months", "Competitor density (~1 km)"], horizontal=True)
    view = props if msa == "All" else props[props.msa == msa]
    if color_by.startswith("%"):
        metric, low, high = view.pct_abr_expiring_24m.fillna(0), "0%", "100%"
    else:
        top = max(int(view.competitor_count.max() or 0), 1)
        metric, low, high = view.competitor_count.fillna(0) / top, "0", f"{top} competitors"
    # Green (low) to red (high); height is annualized base rent.
    m = metric.clip(0, 1)
    view = view.assign(r=(40 + m * 200).astype(int), g=(170 - m * 130).astype(int), elevation=view.abr / 1e3,
                       occupancy=(view.occupancy_rate * 100).round(1),
                       expiring=(view.pct_abr_expiring_24m.fillna(0) * 100).round(1),
                       abr_m=(view.abr / 1e6).round(2))
    st.pydeck_chart(pdk.Deck(
        map_provider="carto", map_style=pdk.map_styles.CARTO_LIGHT,
        initial_view_state=pdk.ViewState(latitude=view.lat.mean(), longitude=view.lon.mean(),
                                         zoom=4.5 if msa == "All" else 10.5, pitch=45),
        layers=[
            # H3 res-9 cell of each asset, extruded by ABR (visible when zoomed into a market)
            pdk.Layer("H3HexagonLayer", view, get_hexagon="h3", get_fill_color="[r, g, 60, 220]",
                      extruded=True, get_elevation="elevation", elevation_scale=1, pickable=True),
            # Asset markers so every property is visible at any zoom level
            pdk.Layer("ScatterplotLayer", view, get_position="[lon, lat]", get_fill_color="[r, g, 60, 200]",
                      get_radius=150, radius_min_pixels=5, radius_max_pixels=14, stroked=True,
                      get_line_color=[255, 255, 255], line_width_min_pixels=1, pickable=True),
        ],
        tooltip={"text": "{property_name}\n{property_type} · {msa}\nABR ${abr_m}M · Occupancy {occupancy}%\n"
                         "ABR expiring ≤ 24 months: {expiring}%\nCompetitors ~1 km: {competitor_count}"},
    ))
    st.markdown(
        f"<div style='display:flex;align-items:center;gap:8px;font-size:0.85rem'>"
        f"<b>{color_by}</b> <span>{low}</span>"
        f"<span style='width:180px;height:12px;border-radius:2px;"
        f"background:linear-gradient(90deg,rgb(40,170,60),rgb(140,105,60),rgb(240,40,60))'></span>"
        f"<span>{high}</span><span style='margin-left:16px'>Marker = property · hex = its H3 cell (res 9), "
        f"height = annualized base rent</span></div>", unsafe_allow_html=True)
    st.dataframe(view[["property_id", "property_name", "property_type", "msa", "neighborhood", "occupancy_rate",
                       "abr", "walt_years", "pct_abr_expiring_24m", "competitor_count"]]
                 .sort_values("pct_abr_expiring_24m", ascending=False), hide_index=True, use_container_width=True,
                 column_config=COLS)

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
    st.dataframe(leases, hide_index=True, use_container_width=True, column_config=COLS)

# ── Lease review ────────────────────────────────────────────────────────────────
with tab_review:
    st.subheader("Leases flagged for review")
    st.caption("A lease abstract is the summary of a lease's key terms (dates, rent, renewal options, co-tenancy, "
               "termination rights) that the pipeline extracts from the signed PDF with ai_extract. Leases are "
               "flagged when the abstract disagrees with the ERP or is missing required fields. Select a row to "
               "review it. Approved corrections are saved to Lakebase and reach the gold tables and Genie on the "
               "next pipeline update.")
    queue = query(f"""
        SELECT a.lease_id, a.tenant_name, a.review_status,
               CASE WHEN d.expiration_mismatch AND d.rent_mismatch THEN 'Lease end and rent'
                    WHEN d.expiration_mismatch THEN 'Lease end' WHEN d.rent_mismatch THEN 'Monthly rent'
                    ELSE 'Incomplete abstract' END AS issue,
               d.erp_lease_end, d.abstract_lease_end, d.erp_monthly_rent, d.abstract_monthly_rent,
               a.abstract_confidence, a.path
        FROM {t('lease_abstract')} a LEFT JOIN {t('lease_discrepancies')} d USING (lease_id)
        WHERE d.lease_id IS NOT NULL OR a.review_status = 'needs_review'
        ORDER BY a.abstract_confidence, a.lease_id""")
    picked = st.dataframe(queue.drop(columns=["path"]), hide_index=True, use_container_width=True,
                          column_config=COLS, on_select="rerun", selection_mode="single-row", key="review_queue")
    rows = picked.selection.rows
    if queue.empty:
        st.info("No leases need review.")
    elif not rows:
        st.info("Select a lease in the table to review it.")
    else:
        row = queue.iloc[rows[0]]
        lease_id = row.lease_id
        st.markdown(f"#### {lease_id} · {row.tenant_name} · {row.issue}")
        if st.button("Load source PDF"):
            pdf = app_client().files.download(row.path.replace("dbfs:", "")).contents.read()
            st.download_button("Download lease PDF", pdf, file_name=f"{lease_id}.pdf", mime="application/pdf")
        # Default the field to the one in dispute, and offer the ERP value as the suggested correction
        default = "lease_end" if row.issue.startswith("Lease end") else \
            "monthly_rent" if row.issue == "Monthly rent" else REVIEWABLE_FIELDS[0]
        field = st.selectbox("Field", REVIEWABLE_FIELDS, index=REVIEWABLE_FIELDS.index(default),
                             key=f"field_{lease_id}")
        current = query(f"SELECT {field}::text AS v FROM {t('lease_abstract')} WHERE lease_id = %s",
                        (lease_id,)).v.iloc[0]
        erp = {"lease_end": row.erp_lease_end, "monthly_rent": row.erp_monthly_rent}.get(field)
        erp = None if pd.isna(erp) else (f"{erp:.2f}" if isinstance(erp, float) else str(erp))
        c1, c2 = st.columns(2)
        c1.metric("Extracted from lease PDF", current if current is not None else "—")
        c2.metric("ERP value", erp or "—")
        with st.form(f"correction_{lease_id}_{field}"):
            corrected = st.text_input("Confirmed value", value=erp or (current or ""))
            if st.form_submit_button("Approve correction", type="primary") and corrected:
                reviewer = st.context.headers.get("x-forwarded-email", "app")
                with pg() as conn:
                    conn.execute("""
                        INSERT INTO app.abstract_review (lease_id, field_name, extracted_value, corrected_value, status, reviewer)
                        VALUES (%s, %s, %s, %s, 'approved', %s)
                        ON CONFLICT (lease_id, field_name) DO UPDATE
                        SET corrected_value = EXCLUDED.corrected_value, reviewer = EXCLUDED.reviewer,
                            status = 'approved', reviewed_at = now()""",
                                 (lease_id, field, current, corrected, reviewer))
                query.clear()
                st.success(f"Approved: {lease_id}.{field} = {corrected}")
    st.subheader("Approved corrections")
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
