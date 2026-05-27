-- ============================================================
-- popemp_colombia.sql
-- Datos de prueba: 13 empleados colombianos para demo AS400
-- SALARY = salario mensual en COP (pesos colombianos)
-- Cubre los 7 tramos de retención Art.383 E.T. (UVT 2024)
-- Ejecutar en librería CMPSYS: RUNSQLSTM SRCSTMF('...')
-- ============================================================

-- Ampliar columna SALARY para pesos colombianos
ALTER TABLE CMPSYS.EMPLOYEE
  ALTER COLUMN SALARY SET DATA TYPE DECIMAL(15,2);

-- Limpiar datos previos (demo fresco)
DELETE FROM CMPSYS.EMPLOYEE;

-- ============================================================
-- TRAMO 0: Sin retención (salario < $4,471,175/mes)
-- ============================================================
INSERT INTO CMPSYS.EMPLOYEE
  (EMPNO, FIRSTNME, MIDINIT, LASTNAME, WORKDEPT, PHONENO,
   HIREDATE, JOB, EDLEVEL, SEX, BIRTHDATE, SALARY, BONUS, COMM)
VALUES
  -- 1 SMLV 2024
  ('000100', 'CARLOS',    'A', 'MENDOZA',   'D11', '1234',
   '2022-03-15', 'OPERARIO', 12, 'M', '1990-05-20', 1300000.00, 0, 0),
  -- 1.25 SMLV
  ('000200', 'DIEGO',     'R', 'PEREZ',     'D11', '1357',
   '2023-02-14', 'OPERARIO', 11, 'M', '1995-10-08', 1625000.00, 0, 0),
  -- 1.5 SMLV — recibe auxilio de transporte
  ('000300', 'ANA',       'M', 'RODRIGUEZ', 'D11', '2345',
   '2021-06-01', 'TECNICO',  14, 'F', '1988-11-10', 2000000.00, 0, 0),
  -- 2.7 SMLV — sin auxilio transporte, sin retención
  ('000400', 'LUIS',      'E', 'GARCIA',    'D21', '3456',
   '2020-01-10', 'ANALISTA', 15, 'M', '1985-07-22', 3500000.00, 0, 0),
  -- 4.0 SMLV — justo bajo el umbral de retención
  ('000500', 'CAROLINA',  'P', 'HERRERA',   'D21', '4444',
   '2019-05-20', 'ANALISTA', 15, 'F', '1986-03-11', 4200000.00, 0, 0);

-- ============================================================
-- TRAMO 1: 19% sobre exceso de 95 UVT ($4.47M–$7.06M/mes)
-- ============================================================
INSERT INTO CMPSYS.EMPLOYEE
  (EMPNO, FIRSTNME, MIDINIT, LASTNAME, WORKDEPT, PHONENO,
   HIREDATE, JOB, EDLEVEL, SEX, BIRTHDATE, SALARY, BONUS, COMM)
VALUES
  ('000600', 'MARIA',     'C', 'TORRES',    'C01', '4567',
   '2019-08-20', 'ANALISTA', 16, 'F', '1983-02-14', 6000000.00, 0, 0),
  ('000700', 'VALENTINA', 'S', 'JIMENEZ',   'B01', '2468',
   '2020-09-01', 'ANALISTA', 15, 'F', '1987-01-19', 6800000.00, 0, 0);

-- ============================================================
-- TRAMO 2: 28% ($7.06M–$16.94M/mes)
-- ============================================================
INSERT INTO CMPSYS.EMPLOYEE
  (EMPNO, FIRSTNME, MIDINIT, LASTNAME, WORKDEPT, PHONENO,
   HIREDATE, JOB, EDLEVEL, SEX, BIRTHDATE, SALARY, BONUS, COMM)
VALUES
  ('000800', 'JORGE',     'H', 'MARTINEZ',  'B01', '5678',
   '2018-04-05', 'JEFE',     17, 'M', '1980-09-30', 10000000.00, 0, 0),
  ('000900', 'PATRICIA',  'L', 'LOPEZ',     'C01', '6789',
   '2017-11-15', 'COORDIN',  16, 'F', '1979-04-18', 15000000.00, 0, 0);

-- ============================================================
-- TRAMO 3: 33% ($16.94M–$30.12M/mes)
-- ============================================================
INSERT INTO CMPSYS.EMPLOYEE
  (EMPNO, FIRSTNME, MIDINIT, LASTNAME, WORKDEPT, PHONENO,
   HIREDATE, JOB, EDLEVEL, SEX, BIRTHDATE, SALARY, BONUS, COMM)
VALUES
  ('001000', 'ANDRES',    'F', 'SILVA',     'A00', '7890',
   '2016-02-28', 'GERENTE',  18, 'M', '1975-12-05', 25000000.00, 0, 0);

-- ============================================================
-- TRAMO 4: 35% ($30.12M–$44.48M/mes)
-- ============================================================
INSERT INTO CMPSYS.EMPLOYEE
  (EMPNO, FIRSTNME, MIDINIT, LASTNAME, WORKDEPT, PHONENO,
   HIREDATE, JOB, EDLEVEL, SEX, BIRTHDATE, SALARY, BONUS, COMM)
VALUES
  ('001100', 'CLAUDIA',   'B', 'VARGAS',    'A00', '8901',
   '2015-07-10', 'DIRECTOR', 18, 'F', '1972-08-25', 40000000.00, 0, 0);

-- ============================================================
-- TRAMO 5: 37% ($44.48M–$108.25M/mes)
-- ============================================================
INSERT INTO CMPSYS.EMPLOYEE
  (EMPNO, FIRSTNME, MIDINIT, LASTNAME, WORKDEPT, PHONENO,
   HIREDATE, JOB, EDLEVEL, SEX, BIRTHDATE, SALARY, BONUS, COMM)
VALUES
  ('001200', 'ROBERTO',   'D', 'CASTRO',    'E01', '9012',
   '2014-03-20', 'DIRECTOR', 19, 'M', '1968-03-12', 70000000.00, 0, 0);

-- ============================================================
-- TRAMO 6: 39% (> $108.25M/mes)
-- ============================================================
INSERT INTO CMPSYS.EMPLOYEE
  (EMPNO, FIRSTNME, MIDINIT, LASTNAME, WORKDEPT, PHONENO,
   HIREDATE, JOB, EDLEVEL, SEX, BIRTHDATE, SALARY, BONUS, COMM)
VALUES
  ('001300', 'ISABELLA',  'G', 'RESTREPO',  'E01', '0123',
   '2010-01-05', 'GERENTE',  20, 'F', '1965-06-30', 150000000.00, 0, 0);

-- Verificar resultado
SELECT EMPNO, TRIM(LASTNAME) AS APELLIDO, TRIM(JOB) AS CARGO,
       SALARY AS SALARIO_MES,
       CASE
         WHEN SALARY < 4471175   THEN 'Tramo 0 - 0%'
         WHEN SALARY < 7059750   THEN 'Tramo 1 - 19%'
         WHEN SALARY < 16943400  THEN 'Tramo 2 - 28%'
         WHEN SALARY < 30121600  THEN 'Tramo 3 - 33%'
         WHEN SALARY < 44476425  THEN 'Tramo 4 - 35%'
         WHEN SALARY < 108249500 THEN 'Tramo 5 - 37%'
         ELSE                         'Tramo 6 - 39%'
       END AS TRAMO_RETENCION
FROM CMPSYS.EMPLOYEE
ORDER BY SALARY;
