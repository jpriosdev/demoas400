# Nómina Colombia IBM i — Plan de Implementación (Parallel Edition)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar un sistema básico de nómina quincenal con reglas colombianas (seguridad social, parafiscales, horas extras, provisiones de prestaciones sociales) sobre IBM i (AS/400), siguiendo la arquitectura de `ibmi-company_system`.

**Architecture:** Nuevo proyecto `ibmi-nomina-colombia/` al mismo nivel que `ibmi-company_system/`. Tablas SQL independientes que referencian `EMPLOYEE`. Lógica de negocio en service program `NOMLIQ.SRVPGM`. Pantallas 5250 DDS con subfiles. GNU Make para build.

**Tech Stack:** SQLRPGLE free-format, DDS display files, DB2 for i SQL, RPGUnit para tests, GNU Make.

---

## Estrategia de paralelismo

El makefile es compartido — ningún subagente lo toca hasta la fase final.
Cada subagente crea SOLO su archivo fuente. El makefile completo se escribe en la Fase 6.

```
Fase 1 (secuencial): Scaffolding + Tablas SQL + Include file
Fase 2 (secuencial): Tests (TDD rojo)
Fase 3 (secuencial): Service program NOMLIQ
Fase 4 (3 EN PARALELO): nomemps.dspf | nomliq.dspf | nomrpt.dspf
Fase 5 (3 EN PARALELO): nomemps.pgm  | nomliqpgm.pgm | nomrptpgm.pgm
Fase 6 (secuencial): Makefile completo + build + tests + verificación
```

---

## Mapa de archivos

```
ibmi-nomina-colombia/
├── qsqlsrc/
│   ├── nomina_emp.table          Datos laborales del empleado (FK → EMPLOYEE)
│   ├── nomina_periodo.table      Períodos quincenales de nómina
│   ├── nomina_liq.table          Liquidaciones (una por empleado por período)
│   └── popperiodo.sqlprc         SP para crear el período quincenal actual
├── qrpgleref/
│   └── nomina.rpgleinc           Constantes legales, DS templates, prototipos
├── qrpglesrc/
│   ├── nomliq.sqlrpgle           Módulo servicio: calcularLiquidacion, guardarLiquidacion, getArlPct
│   ├── nomliq.bnd                Binding file para NOMLIQ.SRVPGM
│   ├── nomemps.pgm.sqlrpgle      Programa: lista empleados con estado de nómina
│   ├── nomliqpgm.pgm.sqlrpgle    Programa: entrada/cálculo de liquidación quincenal
│   └── nomrptpgm.pgm.sqlrpgle    Programa: comprobante de nómina (solo lectura)
├── qddssrc/
│   ├── nomemps.dspf              Pantalla lista empleados (subfile)
│   ├── nomliq.dspf               Pantalla entrada liquidación
│   └── nomrpt.dspf               Pantalla comprobante nómina
├── qtestsrc/
│   └── nomliq.test.sqlrpgle      Tests RPGUnit para calcularLiquidacion
├── makefile                      Escrito completo en Fase 6
└── iproj.json
```

---

## ════════════════════════════════════════
## FASE 1 — Fundación (Secuencial)
## ════════════════════════════════════════

## Task 1: Scaffolding del proyecto

**Files:**
- Create: `ibmi-nomina-colombia/iproj.json`
- Create: carpetas `qsqlsrc/`, `qrpgleref/`, `qrpglesrc/`, `qddssrc/`, `qtestsrc/`, `.logs/`, `.evfevent/`

- [ ] **Step 1: Crear estructura de carpetas**

```bash
mkdir -p ibmi-nomina-colombia/qsqlsrc
mkdir -p ibmi-nomina-colombia/qrpgleref
mkdir -p ibmi-nomina-colombia/qrpglesrc
mkdir -p ibmi-nomina-colombia/qddssrc
mkdir -p ibmi-nomina-colombia/qtestsrc
mkdir -p ibmi-nomina-colombia/.logs
mkdir -p ibmi-nomina-colombia/.evfevent
```

- [ ] **Step 2: Crear iproj.json**

```json
{
  "description": "Nomina Colombia - IBM i payroll system with Colombian labor rules",
  "includePath": [
    "qrpgleref"
  ],
  "curlib": "&CURLIB",
  "objlib": "&CURLIB",
  "preUsrlibl": [
    "&CURLIB",
    "RPGUNIT",
    "QDEVTOOLS"
  ],
  "buildCommand": "/QOpenSys/pkgs/bin/gmake BIN_LIB=&CURLIB"
}
```

- [ ] **Step 3: Commit**

```bash
git add ibmi-nomina-colombia/
git commit -m "feat: scaffold ibmi-nomina-colombia project structure"
```

---

## Task 2: Tablas SQL

**Files:**
- Create: `ibmi-nomina-colombia/qsqlsrc/nomina_emp.table`
- Create: `ibmi-nomina-colombia/qsqlsrc/nomina_periodo.table`
- Create: `ibmi-nomina-colombia/qsqlsrc/nomina_liq.table`
- Create: `ibmi-nomina-colombia/qsqlsrc/popperiodo.sqlprc`

> **IMPORTANTE:** No crear ni modificar el makefile. Solo crear los archivos fuente.

- [ ] **Step 1: Crear nomina_emp.table**

```sql
-- Datos laborales colombianos del empleado (extiende EMPLOYEE sin modificarla)
CREATE OR REPLACE TABLE NOMINA_EMP (
  EMPNO          CHAR(6)          NOT NULL,
  TIPO_CONTRATO  CHAR(2)          NOT NULL DEFAULT 'IN',  -- FI=Fijo, IN=Indefinido, OB=Obra
  FECHA_INGRESO  DATE             NOT NULL,
  SALARIO_BASICO DECIMAL(11,2)    NOT NULL,               -- Salario mensual en pesos COP
  NIVEL_RIESGO   SMALLINT         NOT NULL DEFAULT 1,     -- ARL: 1=0.522%, 2=1.044%, 3=2.436%, 4=4.350%, 5=6.960%
  FONDO_PENSION  VARCHAR(30),
  EPS            VARCHAR(30),
  CAJA_COMP      VARCHAR(30),
  ACTIVO         CHAR(1)          NOT NULL DEFAULT 'S',
  PRIMARY KEY (EMPNO),
  FOREIGN KEY (EMPNO) REFERENCES EMPLOYEE(EMPNO)
    ON DELETE RESTRICT
);
```

- [ ] **Step 2: Crear nomina_periodo.table**

```sql
-- Períodos quincenales de nómina
CREATE OR REPLACE TABLE NOMINA_PERIODO (
  PERIODO_ID  CHAR(8)    NOT NULL,    -- Formato: YYYYMMQQ (QQ=01 primera, 02 segunda quincena)
  ANIO        SMALLINT   NOT NULL,
  MES         SMALLINT   NOT NULL,
  QUINCENA    SMALLINT   NOT NULL,   -- 1 = días 1-15, 2 = días 16-último
  FECHA_INI   DATE       NOT NULL,
  FECHA_FIN   DATE       NOT NULL,
  ESTADO      CHAR(2)    NOT NULL DEFAULT 'AB',  -- AB=Abierto, CE=Cerrado, PA=Pagado
  PRIMARY KEY (PERIODO_ID),
  CHECK (QUINCENA IN (1, 2)),
  CHECK (ESTADO IN ('AB', 'CE', 'PA'))
);
```

- [ ] **Step 3: Crear nomina_liq.table**

```sql
-- Liquidación quincenal por empleado por período
CREATE OR REPLACE TABLE NOMINA_LIQ (
  LIQ_ID            INTEGER       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  PERIODO_ID        CHAR(8)       NOT NULL,
  EMPNO             CHAR(6)       NOT NULL,
  -- Entradas
  DIAS_TRAB         SMALLINT      NOT NULL DEFAULT 15,
  HORAS_EXT_DIUR    DECIMAL(5,2)  NOT NULL DEFAULT 0,
  HORAS_EXT_NOC     DECIMAL(5,2)  NOT NULL DEFAULT 0,
  HORAS_EXT_FEST_D  DECIMAL(5,2)  NOT NULL DEFAULT 0,
  HORAS_EXT_FEST_N  DECIMAL(5,2)  NOT NULL DEFAULT 0,
  HORAS_REC_NOC     DECIMAL(5,2)  NOT NULL DEFAULT 0,
  OTRAS_DED         DECIMAL(11,2) NOT NULL DEFAULT 0,
  -- Devengados
  SALARIO_QUINCENA  DECIMAL(11,2) NOT NULL DEFAULT 0,
  AUX_TRANSPORTE    DECIMAL(9,2)  NOT NULL DEFAULT 0,
  VALOR_HEXT        DECIMAL(11,2) NOT NULL DEFAULT 0,
  TOTAL_DEVENGADO   DECIMAL(11,2) NOT NULL DEFAULT 0,
  -- Deducciones empleado
  SALUD_EMP         DECIMAL(9,2)  NOT NULL DEFAULT 0,
  PENSION_EMP       DECIMAL(9,2)  NOT NULL DEFAULT 0,
  RETENCION_FTE     DECIMAL(11,2) NOT NULL DEFAULT 0,
  TOTAL_DEDUCCION   DECIMAL(11,2) NOT NULL DEFAULT 0,
  NETO_PAGAR        DECIMAL(11,2) NOT NULL DEFAULT 0,
  -- Aportes empleador (costo empresa, no afectan neto empleado)
  SALUD_EMP_COMP    DECIMAL(9,2)  NOT NULL DEFAULT 0,
  PENSION_EMP_COMP  DECIMAL(9,2)  NOT NULL DEFAULT 0,
  ARL               DECIMAL(9,2)  NOT NULL DEFAULT 0,
  SENA              DECIMAL(9,2)  NOT NULL DEFAULT 0,
  ICBF              DECIMAL(9,2)  NOT NULL DEFAULT 0,
  CAJA_COMP         DECIMAL(9,2)  NOT NULL DEFAULT 0,
  TOTAL_APORTES_EMP DECIMAL(11,2) NOT NULL DEFAULT 0,
  -- Provisiones prestaciones sociales
  PROV_CESANTIAS    DECIMAL(9,2)  NOT NULL DEFAULT 0,
  PROV_INT_CES      DECIMAL(9,2)  NOT NULL DEFAULT 0,
  PROV_PRIMA        DECIMAL(9,2)  NOT NULL DEFAULT 0,
  PROV_VACACIONES   DECIMAL(9,2)  NOT NULL DEFAULT 0,
  TOTAL_PROVISIONES DECIMAL(11,2) NOT NULL DEFAULT 0,
  COSTO_TOTAL       DECIMAL(11,2) NOT NULL DEFAULT 0,
  -- Control
  ESTADO            CHAR(2)       NOT NULL DEFAULT 'CA',  -- CA=Calculado, AP=Aprobado, PA=Pagado
  TS_LIQUIDADO      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (PERIODO_ID) REFERENCES NOMINA_PERIODO(PERIODO_ID),
  FOREIGN KEY (EMPNO) REFERENCES EMPLOYEE(EMPNO),
  UNIQUE (PERIODO_ID, EMPNO),
  CHECK (ESTADO IN ('CA', 'AP', 'PA'))
);
```

- [ ] **Step 4: Crear popperiodo.sqlprc**

```sql
-- Crea el período quincenal para el mes/año indicado
CREATE OR REPLACE PROCEDURE POPPERIODO (
  IN P_ANIO    SMALLINT,
  IN P_MES     SMALLINT,
  IN P_QNA     SMALLINT  -- 1 o 2
)
LANGUAGE SQL
MODIFIES SQL DATA
P1: BEGIN
  DECLARE V_PER_ID  CHAR(8);
  DECLARE V_FECINI  DATE;
  DECLARE V_FECFIN  DATE;

  SET V_PER_ID = CHAR(P_ANIO) CONCAT LPAD(CHAR(P_MES),2,'0')
                 CONCAT LPAD(CHAR(P_QNA),2,'0');

  IF P_QNA = 1 THEN
    SET V_FECINI = DATE(CHAR(P_ANIO) CONCAT '-'
                   CONCAT LPAD(CHAR(P_MES),2,'0') CONCAT '-01');
    SET V_FECFIN = DATE(CHAR(P_ANIO) CONCAT '-'
                   CONCAT LPAD(CHAR(P_MES),2,'0') CONCAT '-15');
  ELSE
    SET V_FECINI = DATE(CHAR(P_ANIO) CONCAT '-'
                   CONCAT LPAD(CHAR(P_MES),2,'0') CONCAT '-16');
    SET V_FECFIN = LAST_DAY(DATE(CHAR(P_ANIO) CONCAT '-'
                   CONCAT LPAD(CHAR(P_MES),2,'0') CONCAT '-01'));
  END IF;

  MERGE INTO NOMINA_PERIODO AS T
    USING (VALUES(V_PER_ID, P_ANIO, P_MES, P_QNA, V_FECINI, V_FECFIN))
      AS S(PERIODO_ID, ANIO, MES, QUINCENA, FECHA_INI, FECHA_FIN)
    ON T.PERIODO_ID = S.PERIODO_ID
    WHEN NOT MATCHED THEN
      INSERT (PERIODO_ID, ANIO, MES, QUINCENA, FECHA_INI, FECHA_FIN, ESTADO)
      VALUES (S.PERIODO_ID, S.ANIO, S.MES, S.QUINCENA, S.FECHA_INI, S.FECHA_FIN, 'AB');

END P1;
```

- [ ] **Step 5: Commit**

```bash
git add ibmi-nomina-colombia/qsqlsrc/
git commit -m "feat: add SQL tables for nomina_emp, nomina_periodo, nomina_liq"
```

---

## Task 3: Include file con constantes y prototipos

**Files:**
- Create: `ibmi-nomina-colombia/qrpgleref/nomina.rpgleinc`

> **IMPORTANTE:** No crear ni modificar el makefile.

- [ ] **Step 1: Crear nomina.rpgleinc**

```rpgle
**free

// ─── Constantes legales Colombia 2024 ────────────────────────────────────────
dcl-c SMMLV          1300000;    // Salario Mínimo Mensual Legal Vigente
dcl-c AUX_TRANSPORTE  162000;    // Auxilio de transporte mensual
dcl-c DIAS_MES            30;    // Colombia usa 30 días para cualquier mes
dcl-c HORAS_DIA            8;    // Jornada ordinaria diaria

// Seguridad social - empleado
dcl-c PCT_SALUD_EMP    0.04;
dcl-c PCT_PENSION_EMP  0.04;

// Seguridad social - empleador
dcl-c PCT_SALUD_COMP   0.085;
dcl-c PCT_PENSION_COMP 0.12;

// Parafiscales - empleador
dcl-c PCT_SENA  0.02;
dcl-c PCT_ICBF  0.03;
dcl-c PCT_CAJA  0.04;

// ARL por nivel de riesgo (empleador)
dcl-c ARL_N1  0.00522;
dcl-c ARL_N2  0.01044;
dcl-c ARL_N3  0.02436;
dcl-c ARL_N4  0.04350;
dcl-c ARL_N5  0.06960;

// Recargos sobre hora ordinaria (horas extras)
dcl-c REC_HED   0.25;    // Extra diurna
dcl-c REC_HEN   0.75;    // Extra nocturna
dcl-c REC_HEFD  0.75;    // Extra festivo diurna
dcl-c REC_HEFN  1.10;    // Extra festivo nocturna
dcl-c REC_RNO   0.35;    // Recargo nocturno ordinario (no es hora extra)

// Provisiones prestaciones (tasa por quincena)
dcl-c PCT_CESANTIAS  0.0833;   // 1/12 del salario mensual por mes → /2 por quincena
dcl-c PCT_INT_CES    0.01;     // 1% mensual sobre cesantías
dcl-c PCT_PRIMA      0.0833;
dcl-c PCT_VACACIONES 0.0417;   // 15 días / 360 días

// ─── Data structure: liquidación completa ────────────────────────────────────
dcl-ds nomina_liq_t qualified template;
  found              ind;
  // Identificadores
  empno              char(6);
  periodo_id         char(8);
  // Info del empleado (de consulta, no almacenada en tabla)
  nombre             varchar(50);
  salario_basico     packed(11:2);
  nivel_riesgo       packed(1:0);
  // Entradas del usuario
  dias_trab          packed(3:0);
  horas_ext_diur     packed(5:2);
  horas_ext_noc      packed(5:2);
  horas_ext_fest_d   packed(5:2);
  horas_ext_fest_n   packed(5:2);
  horas_rec_noc      packed(5:2);
  otras_ded          packed(11:2);
  // Devengados
  salario_quincena   packed(11:2);
  aux_transporte     packed(9:2);
  valor_hext         packed(11:2);
  total_devengado    packed(11:2);
  // Deducciones empleado
  salud_emp          packed(9:2);
  pension_emp        packed(9:2);
  retencion_fte      packed(11:2);
  total_deduccion    packed(11:2);
  neto_pagar         packed(11:2);
  // Aportes empleador
  salud_emp_comp     packed(9:2);
  pension_emp_comp   packed(9:2);
  arl                packed(9:2);
  sena               packed(9:2);
  icbf               packed(9:2);
  caja_comp          packed(9:2);
  total_aportes_emp  packed(11:2);
  // Provisiones prestaciones
  prov_cesantias     packed(9:2);
  prov_int_ces       packed(9:2);
  prov_prima         packed(9:2);
  prov_vacaciones    packed(9:2);
  total_provisiones  packed(11:2);
  costo_total        packed(11:2);
end-ds;

// ─── Prototipos exportados por NOMLIQ.SRVPGM ─────────────────────────────────
dcl-pr calcularLiquidacion like(nomina_liq_t) extproc('CALCULARLIQ');
  empno            char(6)      const;
  periodo_id       char(8)      const;
  dias_trab        packed(3:0)  const;
  horas_ext_diur   packed(5:2)  const;
  horas_ext_noc    packed(5:2)  const;
  horas_ext_fest_d packed(5:2)  const;
  horas_ext_fest_n packed(5:2)  const;
  horas_rec_noc    packed(5:2)  const;
  otras_ded        packed(11:2) const;
end-pr;

dcl-pr guardarLiquidacion ind extproc('GUARDARLIQ');
  liq likeds(nomina_liq_t) const;
end-pr;

dcl-pr getArlPct packed(7:5) extproc('GETARLPCT');
  nivel_riesgo packed(1:0) const;
end-pr;
```

- [ ] **Step 2: Commit**

```bash
git add ibmi-nomina-colombia/qrpgleref/nomina.rpgleinc
git commit -m "feat: add nomina.rpgleinc with Colombian payroll constants, DS templates, and prototypes"
```

---

## ════════════════════════════════════════
## FASE 2 — Tests TDD (Secuencial)
## ════════════════════════════════════════

## Task 4: Tests unitarios RPGUnit (deben fallar hasta que Task 5 compile)

**Files:**
- Create: `ibmi-nomina-colombia/qtestsrc/nomliq.test.sqlrpgle`

> **IMPORTANTE:** No crear ni modificar el makefile. El test no compilará hasta que NOMLIQ.SRVPGM exista (Fase 3) — eso es correcto (TDD rojo).

- [ ] **Step 1: Crear nomliq.test.sqlrpgle**

```rpgle
**free
ctl-opt nomain ccsidcvt(*excp) ccsid(*char : *jobrun) BNDDIR('NOM');

/include qinclude,TESTCASE
/copy 'qrpgleref/nomina.rpgleinc'

// ─── Setup: datos de prueba aislados ──────────────────────────────────────────
dcl-proc setUpSuite export;
  setupMockTable('EMPLOYEE');
  exec sql insert into employee (empno, firstnme, midinit, lastname, edlevel)
           values ('T00001', 'Ana',  'M', 'Torres', 1),
                  ('T00002', 'Luis', 'A', 'Gomez',  1);

  setupMockTable('NOMINA_EMP');
  // Empleado con salario mínimo → aplica auxilio transporte
  exec sql insert into nomina_emp (empno, tipo_contrato, fecha_ingreso,
                                    salario_basico, nivel_riesgo, activo)
           values ('T00001', 'IN', '2020-01-15', 1300000, 1, 'S');
  // Empleado con salario > 2 SMMLV → NO aplica auxilio transporte
  exec sql insert into nomina_emp (empno, tipo_contrato, fecha_ingreso,
                                    salario_basico, nivel_riesgo, activo)
           values ('T00002', 'IN', '2019-03-01', 3000000, 3, 'S');

  setupMockTable('NOMINA_PERIODO');
  exec sql insert into nomina_periodo (periodo_id, anio, mes, quincena,
                                        fecha_ini, fecha_fin, estado)
           values ('20260501', 2026, 5, 1, '2026-05-01', '2026-05-15', 'AB');
end-proc;

// ─── Test 1: SMMLV, 15 días, sin horas extras ────────────────────────────────
// Salario: 1.300.000 → quincena: 650.000
// Aux transporte: 81.000 (mitad de 162.000)
// Salud emp: 650.000 * 4% = 26.000
// Pensión emp: 650.000 * 4% = 26.000
// Neto: 650.000 + 81.000 - 26.000 - 26.000 = 679.000
dcl-proc test_saMinimo_sinExtras export;
  dcl-ds actual likeds(nomina_liq_t) inz;

  actual = calcularLiquidacion('T00001' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(actual.found            : 'found debe ser *on');
  assert(actual.salario_quincena = 650000 : 'salario_quincena');
  assert(actual.aux_transporte   =  81000 : 'aux_transporte');
  assert(actual.valor_hext       =      0 : 'valor_hext');
  assert(actual.total_devengado  = 731000 : 'total_devengado');
  assert(actual.salud_emp        =  26000 : 'salud_emp 4%');
  assert(actual.pension_emp      =  26000 : 'pension_emp 4%');
  assert(actual.neto_pagar       = 679000 : 'neto_pagar');
end-proc;

// ─── Test 2: Salario > 2 SMMLV → sin aux transporte ──────────────────────────
// Salario: 3.000.000 → quincena: 1.500.000
// Sin aux transporte (salario > 2 * 1.300.000 = 2.600.000)
// Neto: 1.500.000 - 60.000 - 60.000 = 1.380.000
dcl-proc test_salarioAlto_sinAuxTransporte export;
  dcl-ds actual likeds(nomina_liq_t) inz;

  actual = calcularLiquidacion('T00002' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(actual.found          : 'found debe ser *on');
  assert(actual.aux_transporte = 0       : 'sin aux transporte');
  assert(actual.salud_emp      = 60000   : 'salud_emp 4% de 1500000');
  assert(actual.pension_emp    = 60000   : 'pension_emp 4% de 1500000');
  assert(actual.neto_pagar     = 1380000 : 'neto_pagar');
end-proc;

// ─── Test 3: Horas extras diurnas ─────────────────────────────────────────────
// Salario: 1.300.000 → hora ordinaria: 1.300.000 / 30 / 8 = 5.416,67
// 4 HED: 4 * hora_ord * 1.25
dcl-proc test_horasExtras_diurnas export;
  dcl-ds actual   likeds(nomina_liq_t) inz;
  dcl-s  hora_ord packed(11:4);
  dcl-s  expected packed(11:2);

  hora_ord = 1300000 / 30 / 8;
  expected = 4 * hora_ord * (1 + 0.25);

  actual = calcularLiquidacion('T00001' : '20260501' : 15 :
                                4 : 0 : 0 : 0 : 0 : 0);

  assert(actual.found      : 'found');
  assert(actual.valor_hext = expected : 'valor HED 4 horas');
end-proc;

// ─── Test 4: Aportes empleador nivel riesgo 1 ─────────────────────────────────
// IBC quincena: 650.000
// Salud comp:  650.000 * 8.5%  = 55.250
// Pensión comp: 650.000 * 12%  = 78.000
// SENA:         650.000 * 2%   = 13.000
// ICBF:         650.000 * 3%   = 19.500
// Caja:         650.000 * 4%   = 26.000
dcl-proc test_aportesEmpleador_nivelRiesgo1 export;
  dcl-ds actual likeds(nomina_liq_t) inz;

  actual = calcularLiquidacion('T00001' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(actual.salud_emp_comp   = 55250 : 'salud_emp_comp 8.5%');
  assert(actual.pension_emp_comp = 78000 : 'pension_emp_comp 12%');
  assert(actual.sena             = 13000 : 'sena 2%');
  assert(actual.icbf             = 19500 : 'icbf 3%');
  assert(actual.caja_comp        = 26000 : 'caja 4%');
end-proc;

// ─── Test 5: Provisiones prestaciones sociales ────────────────────────────────
// Base cesantías/prima = salario_quincena + aux_transporte = 650.000 + 81.000 = 731.000
// prov_cesantias: 731.000 * 8.33%
// prov_int_ces:   prov_cesantias * 1%
// prov_prima:     igual a prov_cesantias
// prov_vacaciones: 650.000 * 4.17% (solo salario, sin aux transporte)
dcl-proc test_provisiones_prestaciones export;
  dcl-ds actual   likeds(nomina_liq_t) inz;
  dcl-s  base     packed(11:2);
  dcl-s  exp_ces  packed(9:2);
  dcl-s  exp_vac  packed(9:2);

  base    = 650000 + 81000;
  exp_ces = base * PCT_CESANTIAS;
  exp_vac = 650000 * PCT_VACACIONES;

  actual = calcularLiquidacion('T00001' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(actual.prov_cesantias  = exp_ces              : 'prov_cesantias');
  assert(actual.prov_int_ces    = exp_ces * PCT_INT_CES : 'prov_int_ces 1%');
  assert(actual.prov_prima      = exp_ces              : 'prov_prima = prov_cesantias');
  assert(actual.prov_vacaciones = exp_vac              : 'prov_vacaciones');
end-proc;

// ─── Test 6: Empleado no encontrado → found = *off ────────────────────────────
dcl-proc test_empleadoNoExiste_found_off export;
  dcl-ds actual likeds(nomina_liq_t) inz;

  actual = calcularLiquidacion('XXXXXX' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(NOT actual.found : 'found debe ser *off para empleado inexistente');
end-proc;
```

- [ ] **Step 2: Commit**

```bash
git add ibmi-nomina-colombia/qtestsrc/nomliq.test.sqlrpgle
git commit -m "test: add RPGUnit tests for calcularLiquidacion (TDD red - NOMLIQ.SRVPGM not yet built)"
```

---

## ════════════════════════════════════════
## FASE 3 — Service Program (Secuencial)
## ════════════════════════════════════════

## Task 5: Módulo servicio NOMLIQ

**Files:**
- Create: `ibmi-nomina-colombia/qrpglesrc/nomliq.sqlrpgle`
- Create: `ibmi-nomina-colombia/qrpglesrc/nomliq.bnd`

> **IMPORTANTE:** No crear ni modificar el makefile. Para verificar compilación, usar comandos directos de IBM i.

- [ ] **Step 1: Crear nomliq.sqlrpgle**

```rpgle
**free
ctl-opt nomain;

/copy 'qrpgleref/nomina.rpgleinc'

// ─── calcularLiquidacion ──────────────────────────────────────────────────────
// Calcula todos los conceptos de una quincena colombiana para un empleado.
// Retorna nomina_liq_t con found=*off si el empleado no existe en NOMINA_EMP.
dcl-proc calcularLiquidacion export;
  dcl-pi *n like(nomina_liq_t);
    empno            char(6)      const;
    periodo_id       char(8)      const;
    dias_trab        packed(3:0)  const;
    horas_ext_diur   packed(5:2)  const;
    horas_ext_noc    packed(5:2)  const;
    horas_ext_fest_d packed(5:2)  const;
    horas_ext_fest_n packed(5:2)  const;
    horas_rec_noc    packed(5:2)  const;
    otras_ded        packed(11:2) const;
  end-pi;

  dcl-ds liq     likeds(nomina_liq_t) inz;
  dcl-s  hora_ord packed(11:4);
  dcl-s  ibc      packed(11:2);
  dcl-s  arl_pct  packed(7:5);
  dcl-s  nombre   varchar(50);

  // Obtener datos laborales del empleado
  exec sql
    select ne.salario_basico,
           ne.nivel_riesgo,
           trim(e.firstnme) concat ' ' concat trim(e.lastname)
      into :liq.salario_basico,
           :liq.nivel_riesgo,
           :nombre
      from nomina_emp ne
      join employee   e  on e.empno = ne.empno
     where ne.empno  = :empno
       and ne.activo = 'S';

  if sqlcode <> 0;
    liq.found = *off;
    return liq;
  endif;

  liq.found      = *on;
  liq.empno      = empno;
  liq.periodo_id = periodo_id;
  liq.nombre     = nombre;
  liq.dias_trab  = dias_trab;
  liq.horas_ext_diur   = horas_ext_diur;
  liq.horas_ext_noc    = horas_ext_noc;
  liq.horas_ext_fest_d = horas_ext_fest_d;
  liq.horas_ext_fest_n = horas_ext_fest_n;
  liq.horas_rec_noc    = horas_rec_noc;
  liq.otras_ded        = otras_ded;

  // ── Devengados ──────────────────────────────────────────────────────────────
  // Colombia: mes = 30 días siempre (art. 134 CST)
  liq.salario_quincena = (liq.salario_basico / DIAS_MES) * dias_trab;

  // Auxilio de transporte: aplica si salario <= 2 SMMLV (art. 7 Ley 1ª/1963)
  if liq.salario_basico <= (2 * SMMLV);
    liq.aux_transporte = AUX_TRANSPORTE / 2;  // mitad por quincena
  else;
    liq.aux_transporte = 0;
  endif;

  // Hora ordinaria base para horas extras
  hora_ord = liq.salario_basico / DIAS_MES / HORAS_DIA;

  liq.valor_hext =
      (horas_ext_diur   * hora_ord * (1 + REC_HED))  +
      (horas_ext_noc    * hora_ord * (1 + REC_HEN))  +
      (horas_ext_fest_d * hora_ord * (1 + REC_HEFD)) +
      (horas_ext_fest_n * hora_ord * (1 + REC_HEFN)) +
      (horas_rec_noc    * hora_ord * REC_RNO);

  liq.total_devengado = liq.salario_quincena + liq.aux_transporte + liq.valor_hext;

  // ── IBC (Ingreso Base de Cotización) ────────────────────────────────────────
  // Excluye auxilio de transporte. Mín = SMMLV/2, Máx = 25 SMMLV/2
  ibc = liq.salario_quincena + liq.valor_hext;
  if ibc < (SMMLV / 2);
    ibc = SMMLV / 2;
  endif;
  if ibc > (SMMLV * 25 / 2);
    ibc = SMMLV * 25 / 2;
  endif;

  // ── Deducciones empleado ────────────────────────────────────────────────────
  liq.salud_emp       = ibc * PCT_SALUD_EMP;
  liq.pension_emp     = ibc * PCT_PENSION_EMP;
  liq.retencion_fte   = 0;  // Retención en fuente: fase futura
  liq.total_deduccion = liq.salud_emp + liq.pension_emp +
                        liq.retencion_fte + otras_ded;
  liq.neto_pagar      = liq.total_devengado - liq.total_deduccion;

  // ── Aportes empleador ───────────────────────────────────────────────────────
  arl_pct = getArlPct(liq.nivel_riesgo);
  liq.salud_emp_comp   = ibc * PCT_SALUD_COMP;
  liq.pension_emp_comp = ibc * PCT_PENSION_COMP;
  liq.arl              = ibc * arl_pct;
  liq.sena             = ibc * PCT_SENA;
  liq.icbf             = ibc * PCT_ICBF;
  liq.caja_comp        = ibc * PCT_CAJA;
  liq.total_aportes_emp = liq.salud_emp_comp + liq.pension_emp_comp +
                          liq.arl + liq.sena + liq.icbf + liq.caja_comp;

  // ── Provisiones prestaciones sociales ───────────────────────────────────────
  // Base cesantías/prima incluye auxilio transporte (art. 249 CST)
  // Vacaciones: solo sobre salario (art. 192 CST)
  liq.prov_cesantias  = (liq.salario_quincena + liq.aux_transporte) * PCT_CESANTIAS;
  liq.prov_int_ces    = liq.prov_cesantias * PCT_INT_CES;
  liq.prov_prima      = (liq.salario_quincena + liq.aux_transporte) * PCT_PRIMA;
  liq.prov_vacaciones = liq.salario_quincena * PCT_VACACIONES;
  liq.total_provisiones = liq.prov_cesantias + liq.prov_int_ces +
                          liq.prov_prima + liq.prov_vacaciones;

  // Costo total empresa = devengado + aportes + provisiones
  liq.costo_total = liq.total_devengado + liq.total_aportes_emp + liq.total_provisiones;

  return liq;
end-proc;

// ─── guardarLiquidacion ───────────────────────────────────────────────────────
// Inserta o actualiza la liquidación en NOMINA_LIQ.
// Retorna *on si sqlcode = 0.
dcl-proc guardarLiquidacion export;
  dcl-pi *n ind;
    liq likeds(nomina_liq_t) const;
  end-pi;

  dcl-s cnt int(5);

  exec sql select count(*) into :cnt
             from nomina_liq
            where empno      = :liq.empno
              and periodo_id = :liq.periodo_id;

  if cnt > 0;
    exec sql
      update nomina_liq set
        dias_trab        = :liq.dias_trab,
        horas_ext_diur   = :liq.horas_ext_diur,
        horas_ext_noc    = :liq.horas_ext_noc,
        horas_ext_fest_d = :liq.horas_ext_fest_d,
        horas_ext_fest_n = :liq.horas_ext_fest_n,
        horas_rec_noc    = :liq.horas_rec_noc,
        otras_ded        = :liq.otras_ded,
        salario_quincena = :liq.salario_quincena,
        aux_transporte   = :liq.aux_transporte,
        valor_hext       = :liq.valor_hext,
        total_devengado  = :liq.total_devengado,
        salud_emp        = :liq.salud_emp,
        pension_emp      = :liq.pension_emp,
        retencion_fte    = :liq.retencion_fte,
        total_deduccion  = :liq.total_deduccion,
        neto_pagar       = :liq.neto_pagar,
        salud_emp_comp   = :liq.salud_emp_comp,
        pension_emp_comp = :liq.pension_emp_comp,
        arl              = :liq.arl,
        sena             = :liq.sena,
        icbf             = :liq.icbf,
        caja_comp        = :liq.caja_comp,
        total_aportes_emp  = :liq.total_aportes_emp,
        prov_cesantias   = :liq.prov_cesantias,
        prov_int_ces     = :liq.prov_int_ces,
        prov_prima       = :liq.prov_prima,
        prov_vacaciones  = :liq.prov_vacaciones,
        total_provisiones  = :liq.total_provisiones,
        costo_total      = :liq.costo_total,
        estado           = 'CA',
        ts_liquidado     = current_timestamp
      where empno      = :liq.empno
        and periodo_id = :liq.periodo_id;
  else;
    exec sql
      insert into nomina_liq (
        periodo_id, empno,
        dias_trab, horas_ext_diur, horas_ext_noc,
        horas_ext_fest_d, horas_ext_fest_n, horas_rec_noc, otras_ded,
        salario_quincena, aux_transporte, valor_hext, total_devengado,
        salud_emp, pension_emp, retencion_fte, total_deduccion, neto_pagar,
        salud_emp_comp, pension_emp_comp, arl, sena, icbf, caja_comp,
        total_aportes_emp,
        prov_cesantias, prov_int_ces, prov_prima, prov_vacaciones,
        total_provisiones, costo_total, estado
      ) values (
        :liq.periodo_id, :liq.empno,
        :liq.dias_trab, :liq.horas_ext_diur, :liq.horas_ext_noc,
        :liq.horas_ext_fest_d, :liq.horas_ext_fest_n, :liq.horas_rec_noc,
        :liq.otras_ded,
        :liq.salario_quincena, :liq.aux_transporte, :liq.valor_hext,
        :liq.total_devengado,
        :liq.salud_emp, :liq.pension_emp, :liq.retencion_fte,
        :liq.total_deduccion, :liq.neto_pagar,
        :liq.salud_emp_comp, :liq.pension_emp_comp, :liq.arl,
        :liq.sena, :liq.icbf, :liq.caja_comp, :liq.total_aportes_emp,
        :liq.prov_cesantias, :liq.prov_int_ces, :liq.prov_prima,
        :liq.prov_vacaciones, :liq.total_provisiones, :liq.costo_total, 'CA'
      );
  endif;

  return sqlcode = 0;
end-proc;

// ─── getArlPct ────────────────────────────────────────────────────────────────
// Retorna la tasa ARL según nivel de riesgo (Decreto 1607/2002).
dcl-proc getArlPct export;
  dcl-pi *n packed(7:5);
    nivel_riesgo packed(1:0) const;
  end-pi;

  select;
    when nivel_riesgo = 1; return ARL_N1;
    when nivel_riesgo = 2; return ARL_N2;
    when nivel_riesgo = 3; return ARL_N3;
    when nivel_riesgo = 4; return ARL_N4;
    when nivel_riesgo = 5; return ARL_N5;
    other;                 return ARL_N1;
  endsl;
end-proc;
```

- [ ] **Step 2: Crear nomliq.bnd**

```rpgle
STRPGMEXP PGMLVL(*CURRENT)
  EXPORT SYMBOL('CALCULARLIQ')
  EXPORT SYMBOL('GUARDARLIQ')
  EXPORT SYMBOL('GETARLPCT')
ENDPGMEXP
```

- [ ] **Step 3: Verificar compilación con comandos directos (sin makefile)**

```bash
# Compilar como MODULE
system "CRTSQLRPGI OBJ(DEV/NOMLIQ) SRCSTMF('ibmi-nomina-colombia/qrpglesrc/nomliq.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) COMPILEOPT('TGTCCSID(*JOB)') RPGPPOPT(*LVL2) OPTION(*EVENTF) OBJTYPE(*MODULE)"

# Crear SRVPGM
system "CRTSRVPGM SRVPGM(DEV/NOMLIQ) MODULE(DEV/NOMLIQ) SRCSTMF('ibmi-nomina-colombia/qrpglesrc/nomliq.bnd') REPLACE(*YES)"

# Crear BNDDIR
system "CRTBNDDIR BNDDIR(DEV/NOM)"
system "ADDBNDDIRE BNDDIR(DEV/NOM) OBJ((*LIBL/NOMLIQ *SRVPGM *IMMED))"
```

Expected: NOMLIQ.SRVPGM creado en DEV sin errores.

- [ ] **Step 4: Compilar y ejecutar tests RPGUnit**

```bash
system "CRTSQLRPGI OBJ(DEV/TNOMLIQS) SRCSTMF('ibmi-nomina-colombia/qtestsrc/nomliq.test.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) COMPILEOPT('TGTCCSID(*JOB) BNDDIR(NOM)') RPGPPOPT(*LVL2) OBJTYPE(*MODULE)"
# Luego en IBM i: RUCRTTSTSPT TSTPGM(DEV/TNOMLIQS)
```

Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ibmi-nomina-colombia/qrpglesrc/nomliq.sqlrpgle \
        ibmi-nomina-colombia/qrpglesrc/nomliq.bnd
git commit -m "feat: implement NOMLIQ service program - Colombian payroll calculation engine"
```

---

## ════════════════════════════════════════
## FASE 4 — Pantallas DDS (3 EN PARALELO)
## ════════════════════════════════════════

> **Ejecutar Tasks 6A, 6B y 6C simultáneamente con 3 subagentes independientes.**
> Cada subagente crea SOLO su archivo `.dspf`. NINGUNO toca el makefile.

---

## Task 6A: nomemps.dspf — Lista de empleados con subfile

**Files:**
- Create: `ibmi-nomina-colombia/qddssrc/nomemps.dspf`

> **IMPORTANTE:** Crear SOLO este archivo. No tocar makefile ni ningún otro archivo.

- [ ] **Step 1: Crear nomemps.dspf**

```dds
     A                                      INDARA
     A                                      CA05(05)
     A                                      CA06(06)
     A                                      CA12(12)
     A          R SFLDTA                    SFL
     A            RRN            4Y 0H
     A            XSEL           1A  B  7  2
     A            XEMPNO         6A  O  7  5
     A            XNOMBRE       25A  O  7 13
     A            XESTADO        2A  O  7 40
     A            XNETO         13S 2O  7 44
     A          R SFLCTL                    SFLCTL(SFLDTA)
     A                                      SFLPAG(0014)
     A                                      SFLSIZ(9999)
     A                                      OVERLAY
     A  85                                  SFLDSPCTL
     A  95                                  SFLDSP
     A N85                                  SFLCLR
     A            SFLRRN         4S 0H      SFLRCDNBR(CURSOR)
     A            XPERIODO       8A  B  3 14
     A                                  1 27'Nomina Colombia'
     A                                      DSPATR(HI)
     A                                      DSPATR(UL)
     A                                  3  2'Periodo:'
     A                                  6  2'Opt'
     A                                      DSPATR(HI)
     A                                      DSPATR(UL)
     A                                  6  5'Empleado'
     A                                      DSPATR(UL)
     A                                  6 13'Nombre'
     A                                      DSPATR(UL)
     A                                  6 40'Est'
     A                                      DSPATR(UL)
     A                                  6 44'Neto a Pagar'
     A                                      DSPATR(UL)
     A          R FOOTER_FMT
     A                                      OVERLAY
     A                                 23  2'F6=Liquidar'
     A                                      COLOR(BLU)
     A                                 23 15'F5=Ver Comprobante'
     A                                      COLOR(BLU)
     A                                 23 35'F12=Salir'
     A                                      COLOR(BLU)
```

- [ ] **Step 2: Commit**

```bash
git add ibmi-nomina-colombia/qddssrc/nomemps.dspf
git commit -m "feat: add nomemps.dspf - employee payroll list with subfile"
```

---

## Task 6B: nomliq.dspf — Entrada de liquidación quincenal

**Files:**
- Create: `ibmi-nomina-colombia/qddssrc/nomliq.dspf`

> **IMPORTANTE:** Crear SOLO este archivo. No tocar makefile ni ningún otro archivo.

- [ ] **Step 1: Crear nomliq.dspf**

```dds
     A                                      INDARA
     A                                      CA05(05)
     A                                      CA10(10)
     A                                      CA12(12)
     A          R LIQFMT
     A                                  1 24'Liquidacion Quincenal Colombia'
     A                                      DSPATR(HI)
     A                                      DSPATR(UL)
     A                                  2  2'Empleado:'
     A            XEMPNO         6A  O  2 12
     A            XNOMBRE       40A  O  2 20
     A                                  3  2'Periodo: '
     A            XPER           8A  O  3 12
     A                                  3 22'Del:'
     A            XFECINI       10A  O  3 27
     A                                  3 39'Al:'
     A            XFECFIN       10A  O  3 43
     A                                  5  2'Dias trabajados:'
     A            XDIAS          2S 0B  5 20
     A                                  7  2'--- Horas Extras ---'
     A                                      COLOR(WHT)
     A                                  8  2'Diurnas (+25%):'
     A            XHED           5S 2B  8 20
     A                                  8 30'Nocturnas (+75%):'
     A            XHEN           5S 2B  8 50
     A                                  9  2'Fest.Diur (+75%):'
     A            XHEFD          5S 2B  9 20
     A                                  9 30'Fest.Noct(+110%):'
     A            XHEFN          5S 2B  9 50
     A                                 10  2'Rec.Noct (+35%):'
     A            XRNO           5S 2B 10 20
     A                                 10 30'Otras Ded.:'
     A            XODED         13S 2B 10 43
     A                                 12  2'--- Devengados ---'
     A                                      COLOR(WHT)
     A                                 13  2'Sal.Quincena:'
     A            XSALQNA       13S 2O 13 17
     A                                 13 34'Aux.Transporte:'
     A            XAUXTRP       11S 2O 13 50
     A                                 14  2'Val.H.Extras:'
     A            XVHEXT        13S 2O 14 17
     A                                 14 34'Total Devengado:'
     A            XTOTDEV       13S 2O 14 51
     A                                 15  2'--- Deducciones Empleado ---'
     A                                      COLOR(WHT)
     A                                 16  2'Salud  4%:'
     A            XSALEMP       11S 2O 16 14
     A                                 16 29'Pension 4%:'
     A            XPENEMP       11S 2O 16 42
     A                                 17  2'Total Deduccion:'
     A            XTOTDED       13S 2O 17 19
     A                                 17 34'NETO A PAGAR:'
     A            XNETO         13S 2O 17 48
     A                                      DSPATR(HI)
     A                                 18  2'--- Aportes Empleador ---'
     A                                      COLOR(WHT)
     A                                 19  2'Salud 8.5%:'
     A            XSALCOMP      11S 2O 19 14
     A                                 19 29'Pension 12%:'
     A            XPENCOMP      11S 2O 19 43
     A                                 20  2'ARL:'
     A            XARL          11S 2O 20  7
     A                                 20 22'SENA 2%:'
     A            XSENA         11S 2O 20 31
     A                                 20 46'ICBF 3%:'
     A            XICBF         11S 2O 20 55
     A                                 21  2'Caja 4%:'
     A            XCAJA         11S 2O 21 12
     A                                 21 27'--- Provisiones ---'
     A                                      COLOR(WHT)
     A                                 22  2'Cesantias:'
     A            XPRCES        11S 2O 22 14
     A                                 22 28'Intereses:'
     A            XPRINT        11S 2O 22 40
     A                                 22 54'Prima:'
     A            XPRPRI        11S 2O 22 61
     A                                 23  2'Vacaciones:'
     A            XPRVAC        11S 2O 23 15
     A                                 23 30'Costo Total:'
     A            XCOSTOT       13S 2O 23 44
     A                                      DSPATR(HI)
     A          R LIQFOOTER
     A                                      OVERLAY
     A                                 24  2'F5=Calcular'
     A                                      COLOR(BLU)
     A                                 24 16'F10=Guardar'
     A                                      COLOR(BLU)
     A                                 24 30'F12=Cancelar'
     A                                      COLOR(BLU)
```

- [ ] **Step 2: Commit**

```bash
git add ibmi-nomina-colombia/qddssrc/nomliq.dspf
git commit -m "feat: add nomliq.dspf - payroll liquidation entry display file"
```

---

## Task 6C: nomrpt.dspf — Comprobante de nómina

**Files:**
- Create: `ibmi-nomina-colombia/qddssrc/nomrpt.dspf`

> **IMPORTANTE:** Crear SOLO este archivo. No tocar makefile ni ningún otro archivo.

- [ ] **Step 1: Crear nomrpt.dspf**

```dds
     A                                      INDARA
     A                                      CA12(12)
     A          R RPTFMT
     A                                  1 26'Comprobante de Nomina Colombia'
     A                                      DSPATR(HI)
     A                                      DSPATR(UL)
     A                                  2  2'Empleado:'
     A            REMPNO         6A  O  2 12
     A            RNOMBRE       40A  O  2 20
     A                                  3  2'Periodo: '
     A            RPER           8A  O  3 12
     A                                  3 22'Del:'
     A            RFECINI       10A  O  3 27
     A                                  3 39'Al:'
     A            RFECFIN       10A  O  3 43
     A                                  3 56'Dias:'
     A            RDIAS          2S 0O  3 62
     A                                  5  2'===== DEVENGADOS ====='
     A                                      DSPATR(HI)
     A                                  6  2'Salario Quincenal:'
     A            RSALQNA       13S 2O  6 22
     A                                  7  2'Auxilio Transporte:'
     A            RAUXTRP       13S 2O  7 22
     A                                  8  2'Valor Horas Extras:'
     A            RVHEXT        13S 2O  8 22
     A                                  9  2'TOTAL DEVENGADO:'
     A            RTOTDEV       13S 2O  9 19
     A                                      DSPATR(HI)
     A                                 11  2'===== DEDUCCIONES EMPLEADO ====='
     A                                      DSPATR(HI)
     A                                 12  2'Salud (4%):'
     A            RSALEMP       13S 2O 12 15
     A                                 13  2'Pension (4%):'
     A            RPENEMP       13S 2O 13 16
     A                                 14  2'Otras Deducciones:'
     A            RODED         13S 2O 14 21
     A                                 15  2'TOTAL DEDUCCIONES:'
     A            RTOTDED       13S 2O 15 21
     A                                      DSPATR(HI)
     A                                 16  2'NETO A PAGAR:'
     A            RNETO         13S 2O 16 16
     A                                      DSPATR(HI)
     A                                 18  2'===== APORTES EMPLEADOR ====='
     A                                      COLOR(WHT)
     A                                 19  2'Salud (8.5%):'
     A            RSALCOMP      13S 2O 19 16
     A                                 19 35'Pension (12%):'
     A            RPENCOMP      13S 2O 19 50
     A                                 20  2'ARL:'
     A            RARL          13S 2O 20  8
     A                                 20 25'SENA (2%):'
     A            RSENA         13S 2O 20 37
     A                                 21  2'ICBF (3%):'
     A            RICBF         13S 2O 21 14
     A                                 21 30'Caja Comp (4%):'
     A            RCAJA         13S 2O 21 47
     A                                 22  2'===== PROVISIONES ====='
     A                                      COLOR(WHT)
     A                                 23  2'Cesantias:'
     A            RPRCES        11S 2O 23 14
     A                                 23 28'Intereses:'
     A            RPRINT        11S 2O 23 40
     A                                 23 54'Prima:'
     A            RPRPRI        11S 2O 23 61
     A          R RPTFOOTER
     A                                      OVERLAY
     A                                 24  2'F12=Volver'
     A                                      COLOR(BLU)
```

- [ ] **Step 2: Commit**

```bash
git add ibmi-nomina-colombia/qddssrc/nomrpt.dspf
git commit -m "feat: add nomrpt.dspf - payroll comprobante display file"
```

---

## ════════════════════════════════════════
## FASE 5 — Programas RPGLE (3 EN PARALELO)
## ════════════════════════════════════════

> **Ejecutar Tasks 7A, 7B y 7C simultáneamente con 3 subagentes independientes.**
> Cada subagente crea SOLO su archivo `.pgm.sqlrpgle`. NINGUNO toca el makefile.
> Prerequisito: Fases 1-4 completas (include file y DDS correspondiente deben existir).

---

## Task 7A: nomemps.pgm.sqlrpgle — Lista de empleados

**Files:**
- Create: `ibmi-nomina-colombia/qrpglesrc/nomemps.pgm.sqlrpgle`

**Context:** Este programa muestra una lista de empleados activos en nómina con su estado de liquidación para el período indicado. El usuario puede seleccionar un empleado con opción 6 (Liquidar) para ir a `NOMLIQPGM`, o con opción 5 (Ver comprobante) para ir a `NOMRPTPGM`. Usa el display file `nomemps.dspf` que tiene formatos `SFLDTA`, `SFLCTL`, y `FOOTER_FMT`.

> **IMPORTANTE:** Crear SOLO este archivo. No tocar makefile ni ningún otro archivo.

- [ ] **Step 1: Crear nomemps.pgm.sqlrpgle**

```rpgle
**free
Ctl-Opt DFTACTGRP(*no) BNDDIR('NOM');

/copy 'qrpgleref/nomina.rpgleinc'

Dcl-C F05   X'35';
Dcl-C F06   X'36';
Dcl-C F12   X'3C';
Dcl-C ENTER X'F1';

Dcl-F nomemps WORKSTN Sfile(SFLDta:Rrn) IndDS(WkStnInd) InfDS(FileInfo);

Dcl-DS WkStnInd;
  SflDspCtl  Ind  Pos(85);
  SflDsp     Ind  Pos(95);
  SflClr     Ind  Pos(75);
End-DS;

Dcl-DS FileInfo;
  FunKey  Char(1)  Pos(369);
End-DS;

Dcl-S Exit  Ind     Inz(*Off);
Dcl-S Rrn   Zoned(4:0) Inz;

// Main
LoadSubfile();
Dow Not Exit;
  Write FOOTER_FMT;
  Exfmt SFLCTL;
  Select;
    When FunKey = F12;  Exit = *On;
    When FunKey = F06;  HandleLiquidar();
    When FunKey = F05;  HandleVerRpt();
    When FunKey = ENTER; HandleInputs();
  Endsl;
Enddo;

*INLR = *On;
Return;

// ─────────────────────────────────────────────────────────────────────────────
Dcl-Proc ClearSubfile;
  SflDspCtl = *Off;
  SflDsp    = *Off;
  Write SFLCTL;
  SflDspCtl = *On;
  Rrn = 0;
End-Proc;

Dcl-Proc LoadSubfile;
  Dcl-S lEmpNo  Char(6);
  Dcl-S lNombre Varchar(50);
  Dcl-S lEstado Char(2);
  Dcl-S lNeto   Packed(13:2);
  Dcl-S lPer    Char(8);

  ClearSubfile();
  lPer = %Trim(XPERIODO);

  Exec Sql Declare empCur Cursor For
    Select e.empno,
           trim(e.firstnme) concat ' ' concat trim(e.lastname),
           coalesce(nl.estado, '--'),
           coalesce(nl.neto_pagar, 0)
      From nomina_emp ne
      Join employee   e  On e.empno = ne.empno
      Left Join nomina_liq nl On nl.empno = ne.empno
                             And nl.periodo_id = :lPer
     Where ne.activo = 'S'
     Order By e.lastname, e.firstnme;

  Exec Sql Open empCur;

  Dou SqlState <> '00000';
    Exec Sql Fetch Next From empCur
             Into :lEmpNo, :lNombre, :lEstado, :lNeto;

    If SqlState = '00000';
      XEMPNO  = lEmpNo;
      XNOMBRE = %Subst(lNombre : 1 : %Min(%Len(lNombre) : 25));
      XESTADO = lEstado;
      XNETO   = lNeto;
      Rrn += 1;
      Write SFLDta;
    Endif;
  Enddo;

  Exec Sql Close empCur;

  If Rrn > 0;
    SflDsp = *On;
    SFLRRN = 1;
  Endif;
End-Proc;

Dcl-Proc HandleInputs;
End-Proc;

Dcl-Proc HandleLiquidar;
  Dcl-S lPer Char(8);

  lPer = %Trim(XPERIODO);
  Dou %EOF(nomemps);
    ReadC SFLDta;
    If %EOF(nomemps); Iter; Endif;
    If %Trim(XSEL) = '6';
      Call 'NOMLIQPGM' Parm(XEMPNO : lPer);
      XSEL = *Blank;
      Update SFLDta;
    Endif;
  Enddo;
  LoadSubfile();
End-Proc;

Dcl-Proc HandleVerRpt;
  Dcl-S lPer Char(8);

  lPer = %Trim(XPERIODO);
  Dou %EOF(nomemps);
    ReadC SFLDta;
    If %EOF(nomemps); Iter; Endif;
    If %Trim(XSEL) = '5';
      Call 'NOMRPTPGM' Parm(XEMPNO : lPer);
      XSEL = *Blank;
      Update SFLDta;
    Endif;
  Enddo;
End-Proc;
```

- [ ] **Step 2: Commit**

```bash
git add ibmi-nomina-colombia/qrpglesrc/nomemps.pgm.sqlrpgle
git commit -m "feat: add NOMEMPS program - employee payroll list with subfile navigation"
```

---

## Task 7B: nomliqpgm.pgm.sqlrpgle — Entrada y cálculo de liquidación

**Files:**
- Create: `ibmi-nomina-colombia/qrpglesrc/nomliqpgm.pgm.sqlrpgle`

**Context:** Este programa recibe `empno` y `periodo_id` como parámetros. Muestra la pantalla de entrada `nomliq.dspf` (formato `LIQFMT` + `LIQFOOTER`). F5=Calcular llama a `calcularLiquidacion` del service program NOMLIQ y muestra el resultado. F10=Guardar calcula y guarda con `guardarLiquidacion`. F12=Cancelar sale sin guardar.

> **IMPORTANTE:** Crear SOLO este archivo. No tocar makefile ni ningún otro archivo.

- [ ] **Step 1: Crear nomliqpgm.pgm.sqlrpgle**

```rpgle
**free
Ctl-Opt DFTACTGRP(*no) BNDDIR('NOM');

Dcl-Pi NOMLIQPGM;
  InEmpNo   Char(6);
  InPeriodo Char(8);
End-Pi;

/copy 'qrpgleref/nomina.rpgleinc'

Dcl-C F05   X'35';
Dcl-C F10   X'3A';
Dcl-C F12   X'3C';

Dcl-F nomliq WORKSTN IndDS(WkStnInd) InfDS(FileInfo);

Dcl-DS WkStnInd;
End-DS;

Dcl-DS FileInfo;
  FunKey  Char(1)  Pos(369);
End-DS;

Dcl-S Exit  Ind           Inz(*Off);
Dcl-Ds liq  LikeDS(nomina_liq_t) Inz;

InicializarPantalla();

Dow Not Exit;
  Write LIQFOOTER;
  Exfmt LIQFMT;
  Select;
    When FunKey = F12;
      Exit = *On;
    When FunKey = F05;
      LeerEntradas();
      Calcular();
      MostrarResultado();
    When FunKey = F10;
      LeerEntradas();
      Calcular();
      MostrarResultado();
      guardarLiquidacion(liq);
      Exit = *On;
  Endsl;
Enddo;

*INLR = *On;
Return;

// ─────────────────────────────────────────────────────────────────────────────
Dcl-Proc InicializarPantalla;
  Dcl-S lFecIni Char(10);
  Dcl-S lFecFin Char(10);

  XEMPNO = InEmpNo;
  XPER   = InPeriodo;
  XDIAS  = 15;

  Exec Sql
    Select trim(firstnme) concat ' ' concat trim(lastname)
      Into :XNOMBRE
      From employee
     Where empno = :InEmpNo;

  Exec Sql
    Select char(fecha_ini, ISO), char(fecha_fin, ISO)
      Into :lFecIni, :lFecFin
      From nomina_periodo
     Where periodo_id = :InPeriodo;
  If SqlCode = 0;
    XFECINI = lFecIni;
    XFECFIN = lFecFin;
  Endif;

  // Cargar entradas previas si ya fue liquidado
  Exec Sql
    Select dias_trab, horas_ext_diur, horas_ext_noc,
           horas_ext_fest_d, horas_ext_fest_n, horas_rec_noc, otras_ded
      Into :XDIAS, :XHED, :XHEN, :XHEFD, :XHEFN, :XRNO, :XODED
      From nomina_liq
     Where empno = :InEmpNo And periodo_id = :InPeriodo;
End-Proc;

Dcl-Proc LeerEntradas;
  liq.empno          = InEmpNo;
  liq.periodo_id     = InPeriodo;
  liq.dias_trab      = XDIAS;
  liq.horas_ext_diur   = XHED;
  liq.horas_ext_noc    = XHEN;
  liq.horas_ext_fest_d = XHEFD;
  liq.horas_ext_fest_n = XHEFN;
  liq.horas_rec_noc    = XRNO;
  liq.otras_ded        = XODED;
End-Proc;

Dcl-Proc Calcular;
  liq = calcularLiquidacion(
          InEmpNo : InPeriodo :
          liq.dias_trab :
          liq.horas_ext_diur  : liq.horas_ext_noc :
          liq.horas_ext_fest_d : liq.horas_ext_fest_n :
          liq.horas_rec_noc   : liq.otras_ded);
End-Proc;

Dcl-Proc MostrarResultado;
  XSALQNA  = liq.salario_quincena;
  XAUXTRP  = liq.aux_transporte;
  XVHEXT   = liq.valor_hext;
  XTOTDEV  = liq.total_devengado;
  XSALEMP  = liq.salud_emp;
  XPENEMP  = liq.pension_emp;
  XTOTDED  = liq.total_deduccion;
  XNETO    = liq.neto_pagar;
  XSALCOMP = liq.salud_emp_comp;
  XPENCOMP = liq.pension_emp_comp;
  XARL     = liq.arl;
  XSENA    = liq.sena;
  XICBF    = liq.icbf;
  XCAJA    = liq.caja_comp;
  XPRCES   = liq.prov_cesantias;
  XPRINT   = liq.prov_int_ces;
  XPRPRI   = liq.prov_prima;
  XPRVAC   = liq.prov_vacaciones;
  XCOSTOT  = liq.costo_total;
End-Proc;
```

- [ ] **Step 2: Commit**

```bash
git add ibmi-nomina-colombia/qrpglesrc/nomliqpgm.pgm.sqlrpgle
git commit -m "feat: add NOMLIQPGM - payroll liquidation entry and calculation program"
```

---

## Task 7C: nomrptpgm.pgm.sqlrpgle — Comprobante de nómina

**Files:**
- Create: `ibmi-nomina-colombia/qrpglesrc/nomrptpgm.pgm.sqlrpgle`

**Context:** Este programa recibe `empno` y `periodo_id` como parámetros. Lee la liquidación guardada en `NOMINA_LIQ` y la muestra en `nomrpt.dspf` (formatos `RPTFMT` + `RPTFOOTER`). Solo F12=Volver para salir. Es pantalla de solo lectura.

> **IMPORTANTE:** Crear SOLO este archivo. No tocar makefile ni ningún otro archivo.

- [ ] **Step 1: Crear nomrptpgm.pgm.sqlrpgle**

```rpgle
**free
Ctl-Opt DFTACTGRP(*no) BNDDIR('NOM');

Dcl-Pi NOMRPTPGM;
  InEmpNo   Char(6);
  InPeriodo Char(8);
End-Pi;

Dcl-F nomrpt WORKSTN IndDS(WkStnInd) InfDS(FileInfo);

Dcl-DS WkStnInd;
End-DS;

Dcl-DS FileInfo;
  FunKey  Char(1)  Pos(369);
End-DS;

CargarComprobante();
Write RPTFOOTER;
Exfmt RPTFMT;

*INLR = *On;
Return;

// ─────────────────────────────────────────────────────────────────────────────
Dcl-Proc CargarComprobante;
  Dcl-S lFecIni Char(10);
  Dcl-S lFecFin Char(10);

  REMPNO = InEmpNo;
  RPER   = InPeriodo;

  Exec Sql
    Select trim(firstnme) concat ' ' concat trim(lastname)
      Into :RNOMBRE
      From employee
     Where empno = :InEmpNo;

  Exec Sql
    Select char(np.fecha_ini, ISO),
           char(np.fecha_fin, ISO),
           nl.dias_trab,
           nl.salario_quincena, nl.aux_transporte,
           nl.valor_hext,       nl.total_devengado,
           nl.salud_emp,        nl.pension_emp,
           nl.otras_ded,        nl.total_deduccion,
           nl.neto_pagar,
           nl.salud_emp_comp,   nl.pension_emp_comp,
           nl.arl,              nl.sena,
           nl.icbf,             nl.caja_comp,
           nl.prov_cesantias,   nl.prov_int_ces,
           nl.prov_prima,       nl.prov_vacaciones
      Into :lFecIni,  :lFecFin,
           :RDIAS,
           :RSALQNA,  :RAUXTRP,
           :RVHEXT,   :RTOTDEV,
           :RSALEMP,  :RPENEMP,
           :RODED,    :RTOTDED,
           :RNETO,
           :RSALCOMP, :RPENCOMP,
           :RARL,     :RSENA,
           :RICBF,    :RCAJA,
           :RPRCES,   :RPRINT,
           :RPRPRI,   :RPRVAC
      From nomina_liq nl
      Join nomina_periodo np On np.periodo_id = nl.periodo_id
     Where nl.empno      = :InEmpNo
       And nl.periodo_id = :InPeriodo;

  If SqlCode = 0;
    RFECINI = lFecIni;
    RFECFIN = lFecFin;
  Endif;
End-Proc;
```

- [ ] **Step 2: Commit**

```bash
git add ibmi-nomina-colombia/qrpglesrc/nomrptpgm.pgm.sqlrpgle
git commit -m "feat: add NOMRPTPGM - payroll comprobante display program"
```

---

## ════════════════════════════════════════
## FASE 6 — Makefile + Build Completo (Secuencial)
## ════════════════════════════════════════

## Task 8: Makefile completo, build, datos de prueba y verificación

**Files:**
- Create: `ibmi-nomina-colombia/makefile`

> Esta tarea escribe el makefile completo de una sola vez (sin conflictos) y verifica que todo el sistema compila y funciona.

- [ ] **Step 1: Crear makefile completo**

```makefile
BIN_LIB=DEV
APP_BNDDIR=NOM
LIBL=$(BIN_LIB)

INCDIR=""
BNDDIR=($(BIN_LIB)/$(APP_BNDDIR))
PREPATH=/QSYS.LIB/$(BIN_LIB).LIB
SHELL=/QOpenSys/usr/bin/qsh

all: .logs .evfevent library \
     $(PREPATH)/NOM.BNDDIR \
     $(PREPATH)/NOMEMPS.PGM \
     $(PREPATH)/NOMLIQPGM.PGM \
     $(PREPATH)/NOMRPTPGM.PGM

# ─── Infraestructura ──────────────────────────────────────────────────────────
.logs:
	mkdir .logs
.evfevent:
	mkdir .evfevent
library:
	-system -q "CRTLIB LIB($(BIN_LIB))"

# ─── Tablas SQL ───────────────────────────────────────────────────────────────
$(PREPATH)/NOMINA_EMP.FILE: qsqlsrc/nomina_emp.table
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "RUNSQLSTM SRCSTMF('qsqlsrc/nomina_emp.table') COMMIT(*NONE)" > .logs/nomina_emp.splf

$(PREPATH)/NOMINA_PERIODO.FILE: qsqlsrc/nomina_periodo.table
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "RUNSQLSTM SRCSTMF('qsqlsrc/nomina_periodo.table') COMMIT(*NONE)" > .logs/nomina_periodo.splf

$(PREPATH)/NOMINA_LIQ.FILE: qsqlsrc/nomina_liq.table \
                             $(PREPATH)/NOMINA_EMP.FILE \
                             $(PREPATH)/NOMINA_PERIODO.FILE
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "RUNSQLSTM SRCSTMF('qsqlsrc/nomina_liq.table') COMMIT(*NONE)" > .logs/nomina_liq.splf

# ─── Service Program NOMLIQ ───────────────────────────────────────────────────
$(PREPATH)/NOMLIQ.MODULE: qrpglesrc/nomliq.sqlrpgle \
                           $(PREPATH)/NOMINA_EMP.FILE \
                           $(PREPATH)/NOMINA_LIQ.FILE
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/NOMLIQ) SRCSTMF('qrpglesrc/nomliq.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) COMPILEOPT('TGTCCSID(*JOB)') RPGPPOPT(*LVL2) OPTION(*EVENTF) OBJTYPE(*MODULE)" > .logs/nomliq.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMLIQ.MBR') TOSTMF('.evfevent/nomliq.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMLIQ.SRVPGM: qrpglesrc/nomliq.bnd \
                           $(PREPATH)/NOMLIQ.MODULE
	-system -q "CRTBNDDIR BNDDIR($(BIN_LIB)/$(APP_BNDDIR))"
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSRVPGM SRVPGM($(BIN_LIB)/NOMLIQ) MODULE($(BIN_LIB)/NOMLIQ) SRCSTMF('qrpglesrc/nomliq.bnd') REPLACE(*YES)" > .logs/nomliq_srv.splf
	-system -q "ADDBNDDIRE BNDDIR($(BIN_LIB)/$(APP_BNDDIR)) OBJ((*LIBL/NOMLIQ *SRVPGM *IMMED))"

$(PREPATH)/NOM.BNDDIR: $(PREPATH)/NOMLIQ.SRVPGM
	-system -q "CRTBNDDIR BNDDIR($(BIN_LIB)/NOM)"
	-system -q "ADDBNDDIRE BNDDIR($(BIN_LIB)/NOM) OBJ((*LIBL/NOMLIQ *SRVPGM *IMMED))"

# ─── Tests RPGUnit ────────────────────────────────────────────────────────────
$(PREPATH)/TNOMLIQS.MODULE: qtestsrc/nomliq.test.sqlrpgle \
                             $(PREPATH)/NOMLIQ.SRVPGM
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/TNOMLIQS) SRCSTMF('qtestsrc/nomliq.test.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) COMPILEOPT('TGTCCSID(*JOB) BNDDIR(NOM)') RPGPPOPT(*LVL2) OPTION(*EVENTF) OBJTYPE(*MODULE)" > .logs/tnomliqs.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/TNOMLIQS.MBR') TOSTMF('.evfevent/tnomliqs.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

# ─── Display Files ────────────────────────────────────────────────────────────
$(PREPATH)/NOMEMPS.FILE: qddssrc/nomemps.dspf
	-system -qi "CRTSRCPF FILE($(BIN_LIB)/QTMPSRC) RCDLEN(112) CCSID(*JOB)"
	system "CPYFRMSTMF FROMSTMF('qddssrc/nomemps.dspf') TOMBR('$(PREPATH)/QTMPSRC.FILE/NOMEMPS.MBR') MBROPT(*REPLACE)"
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTDSPF FILE($(BIN_LIB)/NOMEMPS) SRCFILE($(BIN_LIB)/QTMPSRC) SRCMBR(NOMEMPS) OPTION(*EVENTF)" > .logs/nomemps_dspf.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMEMPS.MBR') TOSTMF('.evfevent/nomemps.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMLIQ.FILE: qddssrc/nomliq.dspf
	-system -qi "CRTSRCPF FILE($(BIN_LIB)/QTMPSRC) RCDLEN(112) CCSID(*JOB)"
	system "CPYFRMSTMF FROMSTMF('qddssrc/nomliq.dspf') TOMBR('$(PREPATH)/QTMPSRC.FILE/NOMLIQ.MBR') MBROPT(*REPLACE)"
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTDSPF FILE($(BIN_LIB)/NOMLIQ) SRCFILE($(BIN_LIB)/QTMPSRC) SRCMBR(NOMLIQ) OPTION(*EVENTF)" > .logs/nomliq_dspf.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMLIQ.MBR') TOSTMF('.evfevent/nomliq.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMRPT.FILE: qddssrc/nomrpt.dspf
	-system -qi "CRTSRCPF FILE($(BIN_LIB)/QTMPSRC) RCDLEN(112) CCSID(*JOB)"
	system "CPYFRMSTMF FROMSTMF('qddssrc/nomrpt.dspf') TOMBR('$(PREPATH)/QTMPSRC.FILE/NOMRPT.MBR') MBROPT(*REPLACE)"
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTDSPF FILE($(BIN_LIB)/NOMRPT) SRCFILE($(BIN_LIB)/QTMPSRC) SRCMBR(NOMRPT) OPTION(*EVENTF)" > .logs/nomrpt_dspf.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMRPT.MBR') TOSTMF('.evfevent/nomrpt.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

# ─── Programas ────────────────────────────────────────────────────────────────
$(PREPATH)/NOMEMPS.PGM: qrpglesrc/nomemps.pgm.sqlrpgle \
                         $(PREPATH)/NOMEMPS.FILE \
                         $(PREPATH)/NOM.BNDDIR \
                         $(PREPATH)/NOMINA_EMP.FILE
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/NOMEMPS) SRCSTMF('qrpglesrc/nomemps.pgm.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) OPTION(*EVENTF) RPGPPOPT(*LVL2) COMPILEOPT('TGTCCSID(*JOB) BNDDIR(NOM) DFTACTGRP(*no)')" > .logs/nomemps.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMEMPS.MBR') TOSTMF('.evfevent/nomemps.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMLIQPGM.PGM: qrpglesrc/nomliqpgm.pgm.sqlrpgle \
                            $(PREPATH)/NOMLIQ.FILE \
                            $(PREPATH)/NOM.BNDDIR
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/NOMLIQPGM) SRCSTMF('qrpglesrc/nomliqpgm.pgm.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) OPTION(*EVENTF) RPGPPOPT(*LVL2) COMPILEOPT('TGTCCSID(*JOB) BNDDIR(NOM) DFTACTGRP(*no)')" > .logs/nomliqpgm.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMLIQPGM.MBR') TOSTMF('.evfevent/nomliqpgm.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMRPTPGM.PGM: qrpglesrc/nomrptpgm.pgm.sqlrpgle \
                            $(PREPATH)/NOMRPT.FILE \
                            $(PREPATH)/NOM.BNDDIR
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/NOMRPTPGM) SRCSTMF('qrpglesrc/nomrptpgm.pgm.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) OPTION(*EVENTF) RPGPPOPT(*LVL2) COMPILEOPT('TGTCCSID(*JOB) BNDDIR(NOM) DFTACTGRP(*no)')" > .logs/nomrptpgm.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMRPTPGM.MBR') TOSTMF('.evfevent/nomrptpgm.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')
```

- [ ] **Step 2: Build completo desde cero**

```bash
cd ibmi-nomina-colombia
gmake BIN_LIB=DEV all
```

Expected: todos los objetos compilados sin errores. Verificar `.logs/*.splf` vacíos de errores.

- [ ] **Step 3: Ejecutar tests RPGUnit**

```bash
gmake BIN_LIB=DEV $(PREPATH)/TNOMLIQS.MODULE
# En IBM i: RUCRTTSTSPT TSTPGM(DEV/TNOMLIQS)
```

Expected: 6 tests PASS.

- [ ] **Step 4: Poblar datos de prueba en IBM i**

```sql
-- Crear período quincenal mayo 2026, primera quincena
CALL POPPERIODO(2026, 5, 1);

-- Inscribir empleados existentes en nómina
INSERT INTO NOMINA_EMP (EMPNO, TIPO_CONTRATO, FECHA_INGRESO,
                         SALARIO_BASICO, NIVEL_RIESGO, ACTIVO)
  SELECT EMPNO, 'IN', COALESCE(HIREDATE, CURRENT DATE),
         COALESCE(SALARY, 1300000), 1, 'S'
  FROM EMPLOYEE
  WHERE SALARY IS NOT NULL
  FETCH FIRST 3 ROWS ONLY;

-- Verificar
SELECT E.EMPNO, E.FIRSTNME, E.LASTNAME,
       NE.SALARIO_BASICO, NE.NIVEL_RIESGO
  FROM EMPLOYEE E JOIN NOMINA_EMP NE ON E.EMPNO = NE.EMPNO;
```

- [ ] **Step 5: Verificar flujo completo en IBM i**

```
1. CALL NOMEMPS → digitar período '20260501', Enter
2. Seleccionar empleado con opción 6 (Liquidar)
3. En NOMLIQPGM: días=15, HED=4 → F5=Calcular → verificar montos calculados
4. F10=Guardar
5. F12=Volver a lista → verificar estado 'CA' y neto en subfile
6. Seleccionar mismo empleado con opción 5 (Ver Comprobante)
7. Verificar todos los conceptos en NOMRPTPGM
8. F12=Volver
```

- [ ] **Step 6: Commit final**

```bash
git add ibmi-nomina-colombia/makefile
git commit -m "feat: add complete makefile and verify full nomina-colombia system build"
```

---

## Resumen de fases y paralelismo

| Fase | Tasks | Modo | Archivos creados |
|---|---|---|---|
| 1 | 1, 2, 3 | Secuencial | iproj.json, 4 SQL files, nomina.rpgleinc |
| 2 | 4 | Secuencial | nomliq.test.sqlrpgle |
| 3 | 5 | Secuencial | nomliq.sqlrpgle, nomliq.bnd |
| 4 | 6A + 6B + 6C | **3 EN PARALELO** | nomemps.dspf, nomliq.dspf, nomrpt.dspf |
| 5 | 7A + 7B + 7C | **3 EN PARALELO** | nomemps.pgm, nomliqpgm.pgm, nomrptpgm.pgm |
| 6 | 8 | Secuencial | makefile (completo) + build + verificación |

## Reglas de negocio implementadas

| Concepto | Base legal | Fórmula |
|---|---|---|
| Salario quincenal | Art. 134 CST | `(salario_mensual / 30) * dias_trab` |
| Aux. transporte | Ley 1ª/1963 | `162.000/2` si salario ≤ 2 SMMLV |
| Hora extra diurna | Art. 168 CST | `hora_ord * 1.25` |
| Hora extra nocturna | Art. 168 CST | `hora_ord * 1.75` |
| Hora extra festiva diurna | Art. 171 CST | `hora_ord * 1.75` |
| Hora extra festiva nocturna | Art. 171 CST | `hora_ord * 2.10` |
| Recargo nocturno ordinario | Art. 168 CST | `hora_ord * 0.35` |
| Salud empleado | Ley 100/93 | `IBC * 4%` |
| Pensión empleado | Ley 100/93 | `IBC * 4%` |
| Salud empleador | Ley 100/93 | `IBC * 8.5%` |
| Pensión empleador | Ley 100/93 | `IBC * 12%` |
| ARL (5 niveles) | Dec. 1607/2002 | `IBC * (0.522% a 6.96%)` |
| SENA | Ley 21/82 | `IBC * 2%` |
| ICBF | Ley 21/82 | `IBC * 3%` |
| Caja de compensación | Ley 21/82 | `IBC * 4%` |
| Prov. cesantías | Art. 249 CST | `(sal + aux_trp) * 8.33%` |
| Prov. int. cesantías | Art. 99 Ley 50/90 | `prov_ces * 1%` |
| Prov. prima | Art. 306 CST | `(sal + aux_trp) * 8.33%` |
| Prov. vacaciones | Art. 186 CST | `sal * 4.17%` |
