# ibmi-company_system — Sistema de Gestión de Empresa

## Propósito
Maestro de empleados y departamentos. Es la **fuente de verdad de datos de personal**
para todo el ecosistema: el sistema de nómina (`ibmi-nomina-colombia`) lee de aquí.

## Módulos del sistema

| Objeto | Tipo | Función |
|--------|------|---------|
| `EMPLOYEE` | Tabla SQL | Maestro de empleados — clave: `EMPNO CHAR(6)` |
| `DEPARTMENT` | Tabla SQL | Maestro de departamentos — clave: `DEPTNO CHAR(3)` |
| `emps.dspf` | Display File | Lista de empleados con subfile (XID, XNAME, XJOB) |
| `depts.dspf` | Display File | Lista de departamentos con subfile |
| `nemp.dspf` | Display File | Alta de nuevo empleado |
| `popemp.sqlprc` | SQL Procedure | Poblar datos de prueba de empleados |
| `popdept.sqlprc` | SQL Procedure | Poblar datos de prueba de departamentos |

## Estructura de la tabla EMPLOYEE

```sql
EMPNO     CHAR(6)        -- Clave primaria, referenciada como LIQEMP en nomina
FIRSTNME  VARCHAR(12)    -- Nombre
MIDINIT   CHAR(1)        -- Inicial del segundo nombre
LASTNAME  VARCHAR(15)    -- Apellido
WORKDEPT  CHAR(3)        -- FK a DEPARTMENT.DEPTNO
PHONENO   CHAR(4)        -- Extension telefonica
HIREDATE  DATE           -- Fecha de ingreso (usado en cesantias definitivas)
JOB       CHAR(8)        -- Cargo (determina nivel de riesgo ARL en nomina)
EDLEVEL   SMALLINT       -- Nivel educativo
SEX       CHAR(1)        -- Genero
BIRTHDATE DATE           -- Fecha de nacimiento
SALARY    DECIMAL(9,2)   -- Salario mensual — BASE DE TODOS LOS CALCULOS DE NOMINA
BONUS     DECIMAL(9,2)   -- Bono
COMM      DECIMAL(9,2)   -- Comision
```

## Integración con otros sistemas
- **ibmi-nomina-colombia**: Lee EMPLOYEE via `SELECT ... FROM CMPSYS.EMPLOYEE`
  en `NOMLIQPGM.rpgle`. La clave `EMPNO` es el vínculo entre sistemas.
- **intERPrise**: Los departamentos de DEPARTMENT mapean a centros de costo en GL.

## Biblioteca en producción
`CMPSYS` — referenciada como `CMPSYS.EMPLOYEE` en las consultas SQL cross-library de nómina.
