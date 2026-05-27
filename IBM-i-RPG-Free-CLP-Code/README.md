# IBM-i-RPG-Free-CLP-Code — Librería de Utilidades y Ejemplos IBM i

## Propósito
Colección de utilidades, patrones y ejemplos IBM i reutilizables.
**Usadas activamente en ibmi-nomina-colombia** como componentes de infraestructura.

## Índice de utilidades

| Carpeta | Función | Usada en sistema |
|---------|---------|-----------------|
| `DATE_UDF/` | SQL UDF: convierte fechas legacy a DATE ISO | `NOMCALCSR` — días acumulados para cesantías |
| `DATEADJ/` | Comando CL: sumar/restar días a una fecha | `NOMLIQPGM` — último día del mes del período |
| `5250_Subfile/` | Patrón completo subfile interactivo con service programs | `NOMLIQPGM` — lista de empleados navegable |
| `SQL_SKELETON/` | Template batch con SQL embedido, cursor y error handling | `NOMCONTPGM` — cursor de contabilización |
| `RcdLckDsp/` | Visualización estándar de bloqueos de registro | `NOMLIQPGM` — prevención doble liquidación |
| `Printing/` | Impresión sin O-Specs ni printer file externo | `NOMRPTPGM` — comprobante impreso |
| `USPS_Address/` | Llamadas HTTP via `QSYS2.HTTP_GET/POST` desde RPG | `NOMCONTPGM` — HTTP a intERPrise GL |
| `Service_Pgms/` | Patrones de service programs y binding directories | `NOMCALCSR` — estructura srvpgm |
| `PGM_REFS/` | SQL Procedure para analizar dependencias entre programas | Análisis de impacto cross-módulos |
| `APIs/` | Llamadas a IBM i APIs desde CLP y RPG | Integración con system APIs |
| `BASE36/` | Service program — incremento de strings alfanuméricos | Generación de IDs en otros módulos |
| `Copy_Mbrs/` | Copybooks compartidos: SRV_MSG_P, SRV_STE_P | Mensajería estándar |

## Utilidades críticas para el demo de integración

### DATE_UDF — Conversión de Fechas Legacy
Ubicación: `DATE_UDF/`
Función: SQL UDF que convierte fechas en formato legacy (YYYYMMDD numérico) a tipo DATE ISO.
Uso en nómina: calcular días exactos entre `EMPLOYEE.HIREDATE` y fecha de corte para cesantías definitivas.

### DATEADJ — Aritmética de Fechas en CL
Ubicación: `DATEADJ/`
Función: Comando CL para sumar o restar días/meses/años a una fecha.
Uso en nómina: `NOMLIQPGM.srCalcFechasPeriodo` necesita calcular el último día del mes.

### SQL_SKELETON — Template de Programa Batch
Ubicación: `SQL_SKELETON/`
Función: Estructura estándar de programa batch con cursor SQL, manejo de SQLCODE y commit/rollback.
Uso en nómina: `NOMCONTPGM` sigue exactamente este patrón para iterar liquidaciones.

### PGM_REFS — Análisis de Dependencias
Ubicación: `PGM_REFS/`
Función: SQL Procedure que usa DSPPGMREF para construir un grafo de dependencias entre programas.
Uso en demo: permite responder "¿qué programas se afectan si cambio X?"

## Notas de integración
Estas utilidades no se copian directamente en los sistemas de negocio. Se referencian
via CALL (programas), SQL FUNCTION (DATE_UDF) o se usan como plantilla de diseño.
Cada programa en `ibmi-nomina-colombia` documenta en su cabecera qué utilidades usa.
