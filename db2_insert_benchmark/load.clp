-- db2 -tvf load.clp   (after db2 connect to MYDB)
-- IMPORT: logged, fires triggers, works anywhere (fast with COMMITCOUNT)
IMPORT FROM /home/user/streamlit_navbar/db2_insert_benchmark/asrate.csv OF DEL COMMITCOUNT 10000 INSERT INTO ASRATE_BENCH (RATE_ID, CURRENCY, RATE_DATE, RATE, SOURCE);
-- LOAD: minimal logging, fastest; table locked/tablespace state during load
-- LOAD FROM /home/user/streamlit_navbar/db2_insert_benchmark/asrate.csv OF DEL INSERT INTO ASRATE_BENCH NONRECOVERABLE;
