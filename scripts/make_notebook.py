"""Build a Databricks-compatible .ipynb from a simple cell list.

Usage (from Python):  make_notebook(path, name, [("md", "# Title"), ("py", "print(1)"), ...])
Cells are written without outputs; outputs come from executed runs (scripts/export_run_notebooks.py).
"""
import json


def _lines(text):
    parts = text.split("\n")
    return [p + "\n" for p in parts[:-1]] + [parts[-1]]


def make_notebook(path, name, cells):
    nb_cells = []
    for kind, text in cells:
        if kind == "md":
            nb_cells.append({"cell_type": "markdown", "metadata": {}, "source": _lines(text)})
        else:
            nb_cells.append({"cell_type": "code", "execution_count": None, "metadata": {},
                             "outputs": [], "source": _lines(text)})
    nb = {
        "cells": nb_cells,
        "metadata": {
            "application/vnd.databricks.v1+notebook": {"language": "python", "notebookName": name},
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 0,
    }
    with open(path, "w") as f:
        f.write(json.dumps(nb, indent=1, ensure_ascii=False))
