# Datos de Prueba Colombianos y Programa EMPMNT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poblar la tabla EMPLOYEE con empleados colombianos que cubran todos los tramos de retención en fuente, y agregar un programa de mantenimiento (EMPMNT) con subfile 5250 que permita listar, agregar, editar y eliminar empleados desde la librería CMPSYS.

**Architecture:** Task 1 crea `popemp_colombia.sql` con ALTER TABLE + 12 INSERTs estáticos cubriendo los 7 tramos de retención del Art.383 E.T. (UVT 2024=$47,065). Task 2 crea el DDS `empmnt.dspf` con formato subfile de lista y formato de detalle. Task 3 crea el programa SQLRPGLE `empmnt.pgm.sqlrpgle` con CRTSQLRPGI. El programa sigue el patrón de `employees.pgm.sqlrpgle` (subfile con INDARA) combinado con la lógica de mantenimiento de `utilidades-ibmi/5250_Subfile/MTNCUSTR.SQLRPGLE`.

**Tech Stack:** DB2 for IBM i SQL (DECIMAL, ALTER TABLE), DDS (SFL/SFLCTL, INDARA, OVERLAY), RPG IV Free-format SQLRPGLE (ILE), CRTSQLRPGI, librería CMPSYS.

---

## File Structure

| Archivo | Acción | Responsabilidad |
|---------|--------|-----------------|
| `gestion-empresa/qsqlsrc/popemp_colombia.sql` | CREATE | ALTER TABLE + 12 INSERTs colombianos, 7 tramos retención |
| `gestion-empresa/qddssrc/empmnt.dspf` | CREATE | DDS: SFLDTA, SFLCTL, CLRSCR, DETALLE, FOOTER, DFOOTER |
| `gestion-empresa/qrpglesrc/empmnt.pgm.sqlrpgle` | CREATE | Programa mantenimiento: list/add/edit/delete empleados |

**Archivos de referencia** (leer antes de implementar, no modificar):
- `gestion-empresa/qsqlsrc/employee.table` — esquema EMPLOYEE (SALARY DECIMAL(9,2) → se amplía a (15,2))
- `gestion-empresa/qddssrc/emps.dspf` — patrón DDS subfile con INDARA
- `gestion-empresa/qrpglesrc/employees.pgm.sqlrpgle` — patrón RPG subfile con INFDS+IndDS
- `gestion-empresa/qrpglesrc/newemp.pgm.sqlrpgle` — patrón RPG add employee
- `gestion-empresa/qrpgleref/constants.rpgleinc` — constantes F01-F24, ENTER
- `utilidades-ibmi/5250_Subfile/MTNCUSTR.SQLRPGLE` — patrón mantenimiento CRUD

---

## Task 1: Datos de prueba — popemp_colombia.sql

**Files:**
- Create: `gestion-empresa/qsqlsrc/popemp_colombia.sql`

Este script amplía la columna SALARY a DECIMAL(15,2) para soportar pesos colombianos, limpia datos previos e inserta 12 empleados colombianos con salarios que cubren los 7 tramos de retención en fuente (Art.383 E.T., UVT 2024 = $47,065).

Tramos mensuales (ingreso base gravable ≈ salario bruto para esta demo):
- Tramo 0: < $4,471,175 → 0% retención
- Tramo 1: $4,471,175–$7,059,750 → 19% sobre exceso de 95 UVT
- Tramo 2: $7,059,750–$16,943,400 → 28% + tarifa fija
- Tramo 3: $16,943,400–$30,121,600 → 33% + tarifa fija
- Tramo 4: $30,121,600–$44,476,425 → 35% + tarifa fija
- Tramo 5: $44,476,425–$108,249,500 → 37% + tarifa fija
- Tramo 6: > $108,249,500 → 39% + tarifa fija

- [ ] **Step 1: Escribir el archivo SQL**

Crear `gestion-empresa/qsqlsrc/popemp_colombia.sql` con el siguiente contenido completo:

```sql
-- ============================================================
-- popemp_colombia.sql
-- Datos de prueba: 12 empleados colombianos para demo AS400
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
```

- [ ] **Step 2: Verificar campos EMPLOYEE vs. INSERTs**

Contar los valores en cada INSERT y compararlos con la definición de employee.table.

La tabla tiene 14 columnas en orden:
`EMPNO, FIRSTNME, MIDINIT, LASTNAME, WORKDEPT, PHONENO, HIREDATE, JOB, EDLEVEL, SEX, BIRTHDATE, SALARY, BONUS, COMM`

Verificar que cada fila VALUES tenga exactamente 14 valores.
- Fila '000100': 'CARLOS', 'A', 'MENDOZA', 'D11', '1234', '2022-03-15', 'OPERARIO', 12, 'M', '1990-05-20', 1300000.00, 0, 0 → 13 campos de datos + EMPNO = 14 ✓
- Repetir mentalmente para cada fila.

Verificar longitudes de campos:
- EMPNO CHAR(6): '000100' = 6 ✓, ..., '001300' = 6 ✓
- FIRSTNME VARCHAR(12): 'VALENTINA' = 9 ✓, 'CAROLINA' = 8 ✓
- LASTNAME VARCHAR(15): 'RODRIGUEZ' = 9 ✓, 'RESTREPO' = 8 ✓
- JOB CHAR(8): 'OPERARIO'=8 ✓, 'ANALISTA'=8 ✓, 'COORDIN'=7 ✓, 'GERENTE'=7 ✓, 'DIRECTOR'=8 ✓, 'JEFE'=4 ✓, 'TECNICO'=7 ✓
- PHONENO CHAR(4): '1234'=4 ✓
- SALARY DECIMAL(15,2) post-ALTER: 150000000.00 = 9 dígitos antes decimal ✓

Si hay alguna discrepancia, corregir en el archivo antes de continuar.

- [ ] **Step 3: Verificar lógica CASE de tramos UVT**

Los límites del CASE deben coincidir con nomcalcsr.rpgle (UVT 2024 = 47,065):
- 95 UVT = 47065 × 95 = **4,471,175** ✓
- 150 UVT = 47065 × 150 = **7,059,750** ✓
- 360 UVT = 47065 × 360 = **16,943,400** ✓
- 640 UVT = 47065 × 640 = **30,121,600** ✓
- 945 UVT = 47065 × 945 = **44,476,425** ✓
- 2300 UVT = 47065 × 2300 = **108,249,500** ✓

Confirmar que cada empleado caiga en el tramo esperado según su SALARY.

- [ ] **Step 4: Commit**

```bash
git add gestion-empresa/qsqlsrc/popemp_colombia.sql
git commit -m "feat: add Colombian test data covering all 7 retención brackets (Art.383 E.T.)"
```

---

## Task 2: DDS — empmnt.dspf

**Files:**
- Create: `gestion-empresa/qddssrc/empmnt.dspf`

Seis formatos de registro en un solo DSPF:
| Formato | Descripción |
|---------|-------------|
| `CLRSCR` | Sin OVERLAY, sin campos — limpia la pantalla |
| `SFLDTA` | SFL — una línea por empleado |
| `SFLCTL` | SFLCTL(SFLDTA) OVERLAY — título, encabezados columnas, área subfile |
| `FOOTER` | OVERLAY — leyenda F-keys para pantalla de lista |
| `DETALLE` | OVERLAY — formulario detalle add/edit/display |
| `DFOOTER` | OVERLAY — leyenda F-keys para pantalla de detalle |

Campos de pantalla (prefijo M = list/subfile, prefijo DE = detalle):
- `MSEL 1A B` — opción del usuario (2/4/5)
- `MNO 6A O` — número de empleado
- `MNOMBRE 27A O` — apellido + nombre concatenados
- `MDEPT 3A O` — departamento
- `MJOB 8A O` — cargo
- `MSAL 15S 2O` — salario mensual
- `SFLRRN 4S 0H` — número relativo de registro (oculto)
- `DEMNO 6A O` — empleado (output, autoasignado)
- `DEFIRST 12A B` — primer nombre
- `DEINIT 1A B` — inicial del medio
- `DELAST 15A B` — apellido
- `DEDEPT 3A B` — departamento
- `DEPHON 4A B` — teléfono
- `DEJOB 8A B` — cargo
- `DESAL 15S 2B` — salario mensual (entrada numérica)
- `DESEX 1A B` — sexo (M/F)
- `DEHIRE L B` — fecha ingreso (tipo L = date)
- `DEERR 50A O` — mensaje de error (color rojo)
- `DEFUNC 10A O` — función actual (Agregar/Editar/Ver)

Indicadores (INDARA):
- Pos 85 = SflDspCtl (mostrar control subfile); cuando OFF activa SFLCLR por N85
- Pos 95 = SflDsp (mostrar registros subfile)
- N85 controla SFLCLR — mismo indicador 85, lógica inversa (patrón emps.dspf)

Teclas de función a nivel de archivo:
- CA03(03) = F3 Salir
- CA06(06) = F6 Agregar
- CA12(12) = F12 Cancelar

- [ ] **Step 1: Crear el DDS con todos los formatos**

Crear `gestion-empresa/qddssrc/empmnt.dspf`:

```dds
     A*============================================================
     A* EMPMNT - Mantenimiento de Empleados
     A* Libreria: CMPSYS  Tabla: EMPLOYEE
     A* Patron: employees.pgm.sqlrpgle + MTNCUSTR.SQLRPGLE
     A*============================================================
     A                                      DSPSIZ(24 80 *DS3)
     A                                      INDARA
     A                                      CA03(03 'F3=Salir')
     A                                      CA06(06 'F6=Agregar')
     A                                      CA12(12 'F12=Cancelar')
     A*------------------------------------------------------------
     A* CLRSCR: sin OVERLAY - limpia pantalla antes del detalle
     A*------------------------------------------------------------
     A          R CLRSCR
     A*------------------------------------------------------------
     A* SFLDTA: registro de subfile (una fila por empleado)
     A*------------------------------------------------------------
     A          R SFLDTA                    SFL
     A            MSEL           1A  B  5  3
     A            MNO            6A  O  5  6
     A            MNOMBRE       27A  O  5 14
     A            MDEPT          3A  O  5 43
     A            MJOB           8A  O  5 48
     A            MSAL          15S 2O  5 58EDTCDE(1)
     A*------------------------------------------------------------
     A* SFLCTL: control del subfile
     A*------------------------------------------------------------
     A          R SFLCTL                    SFLCTL(SFLDTA)
     A                                      SFLPAG(0018)
     A                                      SFLSIZ(9999)
     A                                      OVERLAY
     A  85                                  SFLDSPCTL
     A  95                                  SFLDSP
     A N85                                  SFLCLR
     A            SFLRRN         4S 0H      SFLRCDNBR(CURSOR)
     A                                  1 27'Mantenimiento de Empleados'
     A                                      DSPATR(HI)
     A                                  2  1'  Opciones: 2=Editar  4=Eliminar-
     A                                        5=Visualizar'
     A                                      COLOR(BLU)
     A                                  4  3'Opc'
     A                                      DSPATR(HI UL)
     A                                  4  6'EmpNo'
     A                                      DSPATR(HI UL)
     A                                  4 14'Nombre'
     A                                      DSPATR(HI UL)
     A                                  4 43'Dep'
     A                                      DSPATR(HI UL)
     A                                  4 48'Cargo   '
     A                                      DSPATR(HI UL)
     A                                  4 58'Salario Mensual COP'
     A                                      DSPATR(HI UL)
     A*------------------------------------------------------------
     A* FOOTER: leyenda F-keys para pantalla de lista
     A*------------------------------------------------------------
     A          R FOOTER
     A                                      OVERLAY
     A                                 23  1'F3=Salir  F6=Agregar  F12=Cancel-
     A                                      ar'
     A                                      COLOR(BLU)
     A*------------------------------------------------------------
     A* DETALLE: pantalla de mantenimiento (add/edit/display)
     A*------------------------------------------------------------
     A          R DETALLE
     A                                      OVERLAY
     A            DEFUNC        10A  O  1 27DSPATR(HI)
     A                                  1 38'Empleado'
     A                                  1 47DATE
     A                                      EDTCDE(Y)
     A                                  3  1'No. Empleado'
     A            DEMNO          6A  O  3 15DSPATR(HI)
     A                                  4  1'Nombre'
     A            DEFIRST       12A  B  4 15
     A                                  5  1'Inicial'
     A            DEINIT         1A  B  5 15
     A                                  6  1'Apellido'
     A            DELAST        15A  B  6 15
     A                                  7  1'Departamento'
     A            DEDEPT         3A  B  7 15
     A                                  8  1'Telefono'
     A            DEPHON         4A  B  8 15
     A                                  9  1'Cargo'
     A            DEJOB          8A  B  9 15
     A                                 10  1'Salario/Mes'
     A            DESAL         15S 2B 10 15EDTCDE(1)
     A                                 11  1'Sexo (M/F)'
     A            DESEX          1A  B 11 15
     A                                 12  1'Fecha Ingreso'
     A            DEHIRE          L  B 12 15DATFMT(*ISO)
     A            DEERR         50A  O 20  1COLOR(RED)
     A*------------------------------------------------------------
     A* DFOOTER: leyenda F-keys para pantalla de detalle
     A*------------------------------------------------------------
     A          R DFOOTER
     A                                      OVERLAY
     A                                 23  1'F12=Cancelar  Enter=Guardar/OK'
     A                                      COLOR(BLU)
```

- [ ] **Step 2: Verificar consistencia de nombres de campo**

Confirmar que todos los nombres de campo del DDS coincidan exactamente con los que se usarán en el RPG (Task 3):

Subfile: `MSEL, MNO, MNOMBRE, MDEPT, MJOB, MSAL, SFLRRN`
Detalle: `DEMNO, DEFIRST, DEINIT, DELAST, DEDEPT, DEPHON, DEJOB, DESAL, DESEX, DEHIRE, DEERR, DEFUNC`
Formatos: `CLRSCR, SFLDTA, SFLCTL, FOOTER, DETALLE, DFOOTER`
Indicadores DS: pos 75 = SflClr, pos 85 = SflDspCtl, pos 95 = SflDsp

- [ ] **Step 3: Commit**

```bash
git add gestion-empresa/qddssrc/empmnt.dspf
git commit -m "feat: add EMPMNT display file - subfile list + detail maintenance screen"
```

---

## Task 3: Programa RPG — empmnt.pgm.sqlrpgle

**Files:**
- Create: `gestion-empresa/qrpglesrc/empmnt.pgm.sqlrpgle`

El programa implementa el ciclo completo de mantenimiento de empleados:
- **LoadSubfile**: cursor SQL sobre `CMPSYS.EMPLOYEE`, carga todos en el subfile
- **HandleInputs**: procesa READC del subfile, despacha por opción (2/4/5)
- **ShowDetail**: muestra pantalla DETALLE en modo Editar o Visualizar
- **UpdateEmployee**: UPDATE SQL al guardar edición
- **DeleteEmployee**: DELETE SQL directo (sin confirmación adicional — es demo)
- **AddEmployee**: genera nuevo ID, muestra DETALLE en modo Agregar
- **InsertEmployee**: INSERT SQL del nuevo empleado

Sigue exactamente el patrón de `employees.pgm.sqlrpgle`:
- `Dcl-F empmnt WORKSTN Sfile(SFLDTA:wRRN) IndDS(wStnInd) InfDS(wInfo)`
- INFDS para detectar tecla función vía `wFunKey Char(1) Pos(369)`
- Constantes de tecla de `qrpgleref/constants.rpgleinc`

- [ ] **Step 1: Crear el programa SQLRPGLE**

Crear `gestion-empresa/qrpglesrc/empmnt.pgm.sqlrpgle`:

```rpgle
**free
/title EMPMNT - Mantenimiento de Empleados CMPSYS
//==============================================================
// Programa: EMPMNT
// Libreria: CMPSYS   Tabla: EMPLOYEE
// Funcion : Lista, agrega, edita y elimina empleados
// Patron  : employees.pgm.sqlrpgle + MTNCUSTR.SQLRPGLE
// Compilar: CRTSQLRPGI OBJ(CMPSYS/EMPMNT) SRCFILE(CMPSYS/QRPGLESRC)
//           COMMIT(*NONE) TGTRLS(*CURRENT)
//==============================================================
ctl-opt dftactgrp(*no) actgrp('EMPMNT') option(*nodebugio:*srcstmt);

/include 'qrpgleref/constants.rpgleinc'

// === Archivo de pantalla =====================================
dcl-f empmnt workstn sfile(SFLDTA:wRRN) indds(wStnInd) infds(wInfo);

// === Indicadores de pantalla (INDARA) ========================
// N85 en DDS controla SFLCLR: cuando pos(85) = *off, el subfile se borra
dcl-ds wStnInd;
  wSflDspCtl  ind pos(85);
  wSflDsp     ind pos(95);
end-ds;

// === Informacion de archivo (tecla funcion) ==================
dcl-ds wInfo;
  wFunKey  char(1) pos(369);
end-ds;

// === Variables de trabajo =====================================
dcl-s wRRN    zoned(4:0) inz(0);
dcl-s wExit   ind        inz(*off);

// === Cuerpo principal =========================================
LoadSubfile();

dow not wExit;
  Write FOOTER;
  Exfmt SFLCTL;

  select;
    when wFunKey = F03 or wFunKey = F12;
      wExit = *on;
    when wFunKey = F06;
      AddEmployee();
      LoadSubfile();
    when wFunKey = ENTER;
      HandleInputs();
  endsl;
enddo;

*inlr = *on;
return;

//==============================================================
// ClearSubfile: borra registros del subfile antes de recargar
//==============================================================
dcl-proc ClearSubfile;
  wSflDspCtl = *off;
  wSflDsp    = *off;
  Write SFLCTL;        // escribe con indicadores apagados = borra subfile
  wSflDspCtl = *on;
  wRRN = 0;
end-proc;

//==============================================================
// LoadSubfile: carga todos los empleados de CMPSYS.EMPLOYEE
//==============================================================
dcl-proc LoadSubfile;
  ClearSubfile();

  exec sql declare empAll cursor for
    select empno,
           trim(lastname) concat ', ' concat trim(firstnme),
           coalesce(workdept, '   '),
           coalesce(job, '        '),
           coalesce(salary, 0)
    from cmpsys.employee
    order by lastname, firstnme;

  exec sql open empAll;

  if sqlstate = '00000';
    dou sqlstate <> '00000';
      exec sql fetch next from empAll
        into :MNO, :MNOMBRE, :MDEPT, :MJOB, :MSAL;

      if sqlstate = '00000';
        MSEL  = ' ';
        wRRN += 1;
        write SFLDTA;
      endif;
    enddo;
  endif;

  exec sql close empAll;

  if wRRN > 0;
    wSflDsp = *on;
    SFLRRN  = 1;
  endif;
end-proc;

//==============================================================
// HandleInputs: procesa opciones ingresadas en el subfile
//==============================================================
dcl-proc HandleInputs;
  dou %eof(empmnt);
    readc SFLDTA;
    if %eof(empmnt);
      iter;
    endif;

    select;
      when %trim(MSEL) = '2';        // Editar
        ShowDetail('E': %trim(MNO));
        LoadSubfile();
      when %trim(MSEL) = '4';        // Eliminar
        DeleteEmployee(%trim(MNO));
        LoadSubfile();
      when %trim(MSEL) = '5';        // Visualizar
        ShowDetail('D': %trim(MNO));
        LoadSubfile();
    endsl;

    if MSEL <> ' ';
      MSEL = ' ';
      update SFLDTA;
    endif;
  enddo;
end-proc;

//==============================================================
// ShowDetail: muestra pantalla de detalle para editar o ver
//   pFunc = 'E' (Edit) | 'D' (Display)
//==============================================================
dcl-proc ShowDetail;
  dcl-pi *n;
    pFunc  char(1) value;
    pEmpNo char(6) value;
  end-pi;

  dcl-s lExit ind inz(*off);

  exec sql
    select empno, coalesce(firstnme,' '), coalesce(midinit,' '),
           coalesce(lastname,' '), coalesce(workdept,'   '),
           coalesce(phoneno,'    '), coalesce(job,'        '),
           coalesce(salary,0), coalesce(sex,' '),
           coalesce(hiredate, current_date)
    into  :DEMNO, :DEFIRST, :DEINIT, :DELAST,
          :DEDEPT, :DEPHON,  :DEJOB, :DESAL,
          :DESEX, :DEHIRE
    from  cmpsys.employee
    where empno = :pEmpNo;

  if pFunc = 'E';
    DEFUNC = 'Editar';
  else;
    DEFUNC = 'Visualizar';
  endif;
  DEERR = ' ';

  dow not lExit;
    Write CLRSCR;
    Write DFOOTER;
    Exfmt DETALLE;

    select;
      when wFunKey = F12;
        lExit = *on;
      when wFunKey = ENTER and pFunc = 'E';
        if UpdateEmployee(pEmpNo);
          lExit = *on;
        else;
          DEERR = 'Error al actualizar. Verifique los datos.';
        endif;
      when wFunKey = ENTER and pFunc = 'D';
        lExit = *on;
    endsl;
  enddo;
end-proc;

//==============================================================
// UpdateEmployee: actualiza los campos editables del empleado
//==============================================================
dcl-proc UpdateEmployee;
  dcl-pi *n ind;
    pEmpNo char(6) value;
  end-pi;

  exec sql
    update cmpsys.employee
       set firstnme = :DEFIRST,
           midinit  = :DEINIT,
           lastname = :DELAST,
           workdept = :DEDEPT,
           phoneno  = :DEPHON,
           job      = :DEJOB,
           salary   = :DESAL,
           sex      = :DESEX
     where empno    = :pEmpNo;

  return sqlstate = '00000' or sqlstate = '02000';
end-proc;

//==============================================================
// DeleteEmployee: elimina un empleado por su numero
//==============================================================
dcl-proc DeleteEmployee;
  dcl-pi *n;
    pEmpNo char(6) value;
  end-pi;

  exec sql
    delete from cmpsys.employee
     where empno = :pEmpNo;
end-proc;

//==============================================================
// AddEmployee: genera ID, muestra detalle en modo Agregar
//==============================================================
dcl-proc AddEmployee;
  dcl-s lExit  ind    inz(*off);
  dcl-s lNewId char(6) inz('000001');

  exec sql
    select char(coalesce(max(int(empno)), 0) + 100, 6)
      into :lNewId
      from cmpsys.employee;

  DEMNO   = lNewId;
  DEFIRST = ' ';
  DEINIT  = ' ';
  DELAST  = ' ';
  DEDEPT  = ' ';
  DEPHON  = ' ';
  DEJOB   = ' ';
  DESAL   = 0;
  DESEX   = ' ';
  DEHIRE  = %date();
  DEFUNC  = 'Agregar';
  DEERR   = ' ';

  dow not lExit;
    Write CLRSCR;
    Write DFOOTER;
    Exfmt DETALLE;

    select;
      when wFunKey = F12;
        lExit = *on;
      when wFunKey = ENTER;
        if %trim(DEFIRST) = '';
          DEERR = 'El nombre es obligatorio.';
        elseif %trim(DELAST) = '';
          DEERR = 'El apellido es obligatorio.';
        elseif InsertEmployee();
          lExit = *on;
        else;
          DEERR = 'Error al crear el empleado. Verifique los datos.';
        endif;
    endsl;
  enddo;
end-proc;

//==============================================================
// InsertEmployee: INSERT SQL del nuevo registro
//==============================================================
dcl-proc InsertEmployee;
  dcl-pi *n ind end-pi;

  exec sql
    insert into cmpsys.employee
      (empno, firstnme, midinit, lastname, workdept, phoneno,
       hiredate, job, edlevel, sex, birthdate, salary, bonus, comm)
    values
      (:DEMNO, :DEFIRST, :DEINIT, :DELAST, :DEDEPT, :DEPHON,
       :DEHIRE, :DEJOB, 12, :DESEX, current_date, :DESAL, 0, 0);

  return sqlstate = '00000';
end-proc;
```

- [ ] **Step 2: Verificar nombres de campo DDS ↔ RPG**

Recorrer cada referencia a campo de pantalla en el RPG y confirmar que existe en `empmnt.dspf`:

Subfile (SFLDTA): `MSEL` ✓, `MNO` ✓, `MNOMBRE` ✓, `MDEPT` ✓, `MJOB` ✓, `MSAL` ✓, `SFLRRN` ✓
Detalle (DETALLE): `DEMNO` ✓, `DEFIRST` ✓, `DEINIT` ✓, `DELAST` ✓, `DEDEPT` ✓, `DEPHON` ✓, `DEJOB` ✓, `DESAL` ✓, `DESEX` ✓, `DEHIRE` ✓, `DEERR` ✓, `DEFUNC` ✓
Formatos usados con write/exfmt: `FOOTER` ✓, `SFLCTL` ✓, `CLRSCR` ✓, `DFOOTER` ✓, `DETALLE` ✓, `SFLDTA` (readc/update) ✓

- [ ] **Step 3: Verificar instrucciones de compilación**

El header del programa indica:
```
// Compilar: CRTSQLRPGI OBJ(CMPSYS/EMPMNT) SRCFILE(CMPSYS/QRPGLESRC)
//           COMMIT(*NONE) TGTRLS(*CURRENT)
```

Confirmar que `CRTSQLRPGI` es el comando correcto (no CRTRPGPGM) porque el programa tiene embedded SQL (`exec sql`).

Confirmar que el archivo de pantalla `empmnt` coincide con el nombre del archivo en `dcl-f empmnt workstn`. En IBM i se compilará como `CRTDSPF FILE(CMPSYS/EMPMNT) SRCFILE(CMPSYS/QDDSSRC)`.

- [ ] **Step 4: Commit**

```bash
git add gestion-empresa/qrpglesrc/empmnt.pgm.sqlrpgle
git commit -m "feat: add EMPMNT program - 5250 subfile maintenance for EMPLOYEE table"
```

---

## Task 4: Actualizar documentación en gestion-empresa/README.md

**Files:**
- Modify: `gestion-empresa/readme.md`

- [ ] **Step 1: Leer el README actual**

Leer `gestion-empresa/readme.md` para entender la estructura existente y encontrar la sección de inventario de programas.

- [ ] **Step 2: Agregar EMPMNT al inventario de programas**

En la sección donde se listan los programas (employees, newemp, empdet, depts), agregar una entrada para EMPMNT:

```markdown
| EMPMNT | empmnt.pgm.sqlrpgle | Mantenimiento completo de empleados — subfile 5250 con lista, agregar, editar y eliminar. Llama internamente CMPSYS.EMPLOYEE. F6=Agregar, Opt 2=Editar, Opt 4=Eliminar, Opt 5=Ver. |
```

- [ ] **Step 3: Agregar sección de datos de prueba**

Al final del README (antes de "Integración"), agregar:

```markdown
## Datos de Prueba Colombianos

El script `qsqlsrc/popemp_colombia.sql` inserta 12 empleados que cubren los 7 tramos de retención en fuente (Art.383 E.T., UVT 2024 = $47,065):

| EMPNO  | Empleado          | Cargo    | Salario/Mes      | Tramo Retención |
|--------|-------------------|----------|------------------|-----------------|
| 000100 | MENDOZA, CARLOS   | OPERARIO | $1,300,000       | 0% (1 SMLV)     |
| 000200 | PEREZ, DIEGO      | OPERARIO | $1,625,000       | 0%              |
| 000300 | RODRIGUEZ, ANA    | TECNICO  | $2,000,000       | 0% + Aux.Transp |
| 000400 | GARCIA, LUIS      | ANALISTA | $3,500,000       | 0%              |
| 000500 | HERRERA, CAROLINA | ANALISTA | $4,200,000       | 0% (bajo umbral)|
| 000600 | TORRES, MARIA     | ANALISTA | $6,000,000       | 19%             |
| 000700 | JIMENEZ, VALENTINA| ANALISTA | $6,800,000       | 19%             |
| 000800 | MARTINEZ, JORGE   | JEFE     | $10,000,000      | 28%             |
| 000900 | LOPEZ, PATRICIA   | COORDIN  | $15,000,000      | 28%             |
| 001000 | SILVA, ANDRES     | GERENTE  | $25,000,000      | 33%             |
| 001100 | VARGAS, CLAUDIA   | DIRECTOR | $40,000,000      | 35%             |
| 001200 | CASTRO, ROBERTO   | DIRECTOR | $70,000,000      | 37%             |
| 001300 | RESTREPO, ISABELLA| GERENTE  | $150,000,000     | 39%             |

**Nota:** SALARY almacena el salario mensual en COP (pesos colombianos).  
La columna fue ampliada a `DECIMAL(15,2)` por `popemp_colombia.sql`.
```

- [ ] **Step 4: Commit**

```bash
git add gestion-empresa/readme.md
git commit -m "docs: add EMPMNT to program inventory and Colombian test data table"
```
