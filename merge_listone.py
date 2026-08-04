import pandas as pd

OLD = "lista_calciatori_lista calciatori_mantra_mantramanageriale.xlsx"
NEW = "Quotazioni_Fantacalcio_Stagione_2026_27.xlsx"
OUT = "lista_calciatori_lista calciatori_mantra_mantramanageriale.xlsx"
AGES_CSV = "eta_nuovi.csv"  # Id;Eta, opzionale

old = pd.read_excel(OLD, sheet_name="Lista calciatori")
new = pd.read_excel(NEW, sheet_name="Tutti", header=1)

ages = {}
try:
    ages_df = pd.read_csv(AGES_CSV, sep=";")
    ages = dict(zip(ages_df["Id"], ages_df["Eta"]))
except FileNotFoundError:
    pass

old = old.set_index("#", drop=False)
new = new.set_index("Id", drop=False)

old_ids = set(old.index)
new_ids = set(new.index)
common = old_ids & new_ids
only_old = old_ids - new_ids
only_new = new_ids - old_ids

# 1) overwrite matched rows: R., R.MANTRA, Sq., QUOT.(<-Qt.A M), FVM/1000(<-FVM M)
for pid in common:
    n = new.loc[pid]
    old.loc[pid, "R."] = n["R"]
    old.loc[pid, "R.MANTRA"] = str(n["RM"]).replace(";", "/")
    old.loc[pid, "Sq."] = n["Squadra"]
    old.loc[pid, "QUOT."] = n["Qt.A M"]
    old.loc[pid, "FVM/1000"] = n["FVM M"]

# 2) only-old players -> mark fuori lista
for pid in only_old:
    old.loc[pid, "Fuori lista"] = "*"

# 3) only-new players -> append new rows, FantaSquadra/Costo empty
new_rows = []
for pid in sorted(only_new):
    n = new.loc[pid]
    new_rows.append({
        "#": pid,
        "Nome": n["Nome"],
        "Fuori lista": pd.NA,
        "Sq.": n["Squadra"],
        "Under": ages.get(pid, pd.NA),
        "R.": n["R"],
        "R.MANTRA": str(n["RM"]).replace(";", "/"),
        "PGv": 0,
        "MV": 0,
        "FM": 0,
        "FVM/1000": n["FVM M"],
        "QUOT.": n["Qt.A M"],
        "FantaSquadra": pd.NA,
        "Costo": pd.NA,
    })

result = pd.concat([old.reset_index(drop=True), pd.DataFrame(new_rows)], ignore_index=True)
result = result[["#", "Nome", "Fuori lista", "Sq.", "Under", "R.", "R.MANTRA", "PGv", "MV", "FM", "FVM/1000", "QUOT.", "FantaSquadra", "Costo"]]

with pd.ExcelWriter(OUT, engine="openpyxl") as writer:
    result.to_excel(writer, sheet_name="Lista calciatori", index=False)

print("common:", len(common), "only_old(fuori lista):", len(only_old), "only_new(aggiunti):", len(only_new))
print("eta trovate per nuovi:", sum(1 for pid in only_new if pid in ages), "/", len(only_new))
print("righe totali:", len(result))
