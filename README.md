# demoas400

Repositorio de demostración AS400/IBM i — sistemas de empresa integrados para análisis via LLM.

## Objetivo del proyecto

Demostrar ante clientes cómo los sistemas AS400/IBM i pueden **conectarse y analizarse**
mediante un LLM (Claude) conectado via MCP al repositorio de código fuente en GitHub.

El LLM puede responder preguntas técnicas y de negocio como:
- *¿Dónde está el cálculo de cesantías?*
- *¿Qué módulos existen en el sistema?*
- *¿Cómo fluye un empleado de HR a nómina?*
- *¿Qué programas se ven afectados si cambio el salario?*
- *¿Cómo se contabiliza la nómina en el libro mayor?*

## Proceso de Negocio: Ciclo HCM → Nómina → Contabilidad

```
┌─────────────────────┐    SQL cross-library    ┌──────────────────────────┐
│  ibmi-company_system │ ──────────────────────> │  ibmi-nomina-colombia    │
│                      │   SELECT FROM           │                          │
│  EMPLOYEE (maestro)  │   CMPSYS.EMPLOYEE       │  NOMLIQPGM (liquidar)    │
│  DEPARTMENT          │                         │  NOMCALCSR (calcular)    │
│  EMPNO = clave única │ <── datos empleado ──── │  NOMLIQF   (persistir)   │
└─────────────────────┘                          └──────────┬───────────────┘
                                                            │
                                              HTTP POST JSON│
                                              (NOMCONTPGM)  │
                                                            ▼
                                              ┌─────────────────────────────┐
                                              │  intERPrise ERP             │
                                              │                             │
                                              │  Transport (C server TCP)   │
                                              │  DB Services (UTL130F GL)   │
                                              │  Asiento: DB 51xx / CR 23xx │
                                              └─────────────────────────────┘

IBM-i-RPG-Free-CLP-Code (utilidades transversales):
  DATE_UDF  → NOMCALCSR  |  SQL_SKELETON → NOMCONTPGM
  RcdLckDsp → NOMLIQPGM  |  Printing     → NOMRPTPGM
  USPS_Address (HTTP)    → NOMCONTPGM
```

## Estructura de Módulos

| Módulo | Dominio de Negocio | Rol en el proceso | README |
|--------|--------------------|-------------------|--------|
| [`ibmi-company_system`](ibmi-company_system/) | Gestión de personal | **Fuente de verdad** de empleados | [README](ibmi-company_system/README.md) |
| [`ibmi-nomina-colombia`](ibmi-nomina-colombia/) | Nómina Colombia | **Motor de liquidación** quincenal | [README](ibmi-nomina-colombia/README.md) |
| [`intERPrise`](intERPrise/) | ERP / Contabilidad | **Receptor contable** de nómina | [README](intERPrise/README.md) |
| [`IBM-i-RPG-Free-CLP-Code`](IBM-i-RPG-Free-CLP-Code/) | Utilidades IBM i | **Infraestructura** reutilizable | [README](IBM-i-RPG-Free-CLP-Code/README.md) |

## Preguntas frecuentes (demo LLM)

| Pregunta del cliente | Dónde está la respuesta en el código |
|----------------------|--------------------------------------|
| ¿Dónde está el cálculo de cesantías? | `ibmi-nomina-colombia/qrpglesrc/nomcalcsr.rpgle` → `calcCesantias` |
| ¿Cómo se calcula la retención en la fuente? | `nomcalcsr.rpgle` → `calcRetencion` — tabla progresiva UVT Art.383 E.T. |
| ¿Cómo fluye un empleado de HR a nómina? | `CMPSYS.EMPLOYEE.EMPNO` = `NOMLIQF.LIQEMP` — SQL cross-library en `NOMLIQPGM` |
| ¿Qué módulos existen? | Ver tabla de estructura arriba |
| ¿Cómo se contabiliza la nómina? | `NOMCONTPGM` genera asiento DB 51xx / CR 23xx-26xx en intERPrise |
| ¿Qué es el SENA en nómina? | `calcSENA`: 2% sobre salario, Ley 119/1994 |
| ¿Qué es el auxilio de transporte? | `calcAuxTransporte`: $162.000/mes si salario ≤ 2 SMLV (Decreto 2614/2023) |
| ¿Qué programas afecta cambiar el salario? | `NOMLIQPGM` (lee SALARY), `NOMCALCSR` (base de todos los cálculos) |
| ¿Cuál es el costo total de un empleado? | `NOMLIQF.LIQCST` = devengado + aportes + provisiones |
| ¿Qué utilidades genéricas se reutilizan? | `IBM-i-RPG-Free-CLP-Code`: DATE_UDF, DATEADJ, SQL_SKELETON, RcdLckDsp, Printing |

## Arquitectura técnica

- **Lenguajes**: RPG IV Free-format, SQLRPGLE, DDS, CLLE, C, SQL DDL
- **Integración datos**: SQL cross-library (CMPSYS.EMPLOYEE desde NOMINA)
- **Integración servicios**: HTTP/JSON via QSYS2.HTTP_POST → intERPrise transport server
- **Patrones**: ILE Service Programs, SQL cursors, 5250 Subfiles, Binding Directories
- **Legislación implementada**: CST, Ley 100/1993, Ley 50/1990, Art.383 E.T., Decreto 1607/2002

## Estructura del repositorio

```
demoas400/
├── ibmi-company_system/    # HR: empleados y departamentos
│   ├── qddssrc/            # Display files (emps.dspf, depts.dspf, nemp.dspf)
│   ├── qrpglesrc/          # Programas RPG
│   └── qsqlsrc/            # SQL DDL (employee.table, department.table)
├── ibmi-nomina-colombia/   # Nómina quincenal Colombia
│   ├── qddssrc/            # Display files (nomemps, nomliq, nomrpt)
│   ├── qpfsrc/             # Physical files (nomliqf.pf)
│   ├── qrpglesrc/          # Programas (nomliqpgm, nomrptpgm, nomcontpgm, nomcalcsr)
│   └── qsrvsrc/            # Binding (nomcalcsr.bnd)
├── intERPrise/             # ERP: GL, AP, AR, Cashbook
│   ├── org.i-nterprise.db.services/      # Tablas UTLxxxF + IO services
│   ├── org.i-nterprise.transport.services/ # Servidor HTTP/JSON (C)
│   ├── org.i-nterprise.example/          # Patrón de implementación
│   └── org.i-nterprise.ui.services/      # Frontend PHP
└── IBM-i-RPG-Free-CLP-Code/ # Utilidades: DATE_UDF, DATEADJ, SQL_SKELETON...
```
