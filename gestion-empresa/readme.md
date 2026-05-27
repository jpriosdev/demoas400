# Gestion-Empresa

Sistema de gestión empresarial para AS/400/IBM i con módulos de nómina y gestión de empleados.

## Programas Principales

| Programa | Fuente | Descripción |
|----------|--------|-------------|
| EMPMNT | empmnt.pgm.sqlrpgle | Mantenimiento completo de empleados — subfile 5250 con lista, agregar, editar y eliminar. Archivo de pantalla: empmnt.dspf. F6=Agregar, Opt 2=Editar, Opt 4=Eliminar, Opt 5=Visualizar. |

## Datos de Prueba Colombianos

El script `qsqlsrc/popemp_colombia.sql` inserta 13 empleados que cubren los 7 tramos de retención en fuente (Art.383 E.T., UVT 2024 = $47,065). **SALARY** almacena el salario mensual en COP; la columna fue ampliada a `DECIMAL(15,2)` por el mismo script.

| EMPNO  | Empleado            | Cargo    | Salario/Mes      | Tramo Retención |
|--------|---------------------|----------|------------------|-----------------|
| 000100 | MENDOZA, CARLOS     | OPERARIO | $1,300,000       | 0% (1 SMLV)     |
| 000200 | PEREZ, DIEGO        | OPERARIO | $1,625,000       | 0%              |
| 000300 | RODRIGUEZ, ANA      | TECNICO  | $2,000,000       | 0% + Aux.Transp |
| 000400 | GARCIA, LUIS        | ANALISTA | $3,500,000       | 0%              |
| 000500 | HERRERA, CAROLINA   | ANALISTA | $4,200,000       | 0% (bajo umbral)|
| 000600 | TORRES, MARIA       | ANALISTA | $6,000,000       | 19%             |
| 000700 | JIMENEZ, VALENTINA  | ANALISTA | $6,800,000       | 19%             |
| 000800 | MARTINEZ, JORGE     | JEFE     | $10,000,000      | 28%             |
| 000900 | LOPEZ, PATRICIA     | COORDIN  | $15,000,000      | 28%             |
| 001000 | SILVA, ANDRES       | GERENTE  | $25,000,000      | 33%             |
| 001100 | VARGAS, CLAUDIA     | DIRECTOR | $40,000,000      | 35%             |
| 001200 | CASTRO, ROBERTO     | DIRECTOR | $70,000,000      | 37%             |
| 001300 | RESTREPO, ISABELLA  | GERENTE  | $150,000,000     | 39%             |
