import sqlite3,sys,hashlib
c=sqlite3.connect(sys.argv[1]);h=hashlib.md5()
for (t,) in c.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%' and name not like '%_data' and name not like '%_idx' and name not like '%_config' and name not like '%_docsize' order by name"):
    try: rows=c.execute(f'select * from "{t}"').fetchall()
    except Exception as e: continue
    for r in sorted(map(repr,rows)): h.update(r.encode())
    h.update(t.encode())
print(h.hexdigest())
