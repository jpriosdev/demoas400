# intERPrise — Suite ERP para IBM i

## Propósito
Plataforma ERP completa (GL, AP, AR, Cashbook) basada en IBM i nativo.
Recibe asientos contables de `ibmi-nomina-colombia` via HTTP/JSON.

## Arquitectura de módulos

| Módulo | Directorio | Función |
|--------|-----------|---------|
| DB Services | `org.i-nterprise.db.services/` | Tablas UTLxxxF + IO service programs |
| Transport | `org.i-nterprise.transport.services/` | Servidor HTTP/JSON TCP/IP en C |
| Example | `org.i-nterprise.example/` | Patrón de implementación (CUSMSTF) |
| UI | `org.i-nterprise.ui.services/` | Frontend PHP (easycom) |

## Servidor HTTP (Transport Services)

El módulo `org.i-nterprise.transport.services/` contiene un servidor TCP/IP en C
(`IRP0000.C` → `IRP0004.C`) que acepta requests JSON y los procesa contra DB2.

Endpoint para contabilización de nómina (llamado desde NOMCONTPGM):
```
POST http://<servidor>:<puerto>/api/gl/entry
Content-Type: application/json
{
  "journal": "NOM",
  "period": "YYYYMMQQ",
  "reference": "LIQ-1234",
  "employee": "000100",
  "entries": [
    {"account": "5101", "type": "D", "amount": 1500000.00},
    {"account": "2510", "type": "C", "amount": 1350000.00}
  ]
}
```

## Tablas de base de datos (DB Services — SRCDB2/)

Las tablas siguen el patrón `UTLxxxF` (utility master files):

| Tabla | Función |
|-------|---------|
| `UTL100F` | Account master (plan de cuentas) |
| `UTL110F` | Journal header (encabezado de comprobantes) |
| `UTL130F` | Journal detail (lineas de asiento contable) |
| `UTL135F` | Period control (control de periodos) |
| `UTL140F` | Transaction reference |
| `UTL150F` | Audit trail |

Cada tabla tiene: DDL + RPGLEM (IO service module) + BND (binding definition).

## Service Programs (SRCSRV/)

| SRVPGM | Función |
|--------|---------|
| `ERRSRV` | Manejo estándar de errores (5 módulos ERRSRV@01–@05) |
| `UTLSRV` | Utilidades generales (UTLSRV@01–@02) |

## Integración con ibmi-nomina-colombia
`NOMCONTPGM` (nomina) → HTTP POST → `IRP0000.C` (transport) → `UTL130F` (GL detail)

El asiento contable de nómina usa cuentas PUC Colombia:
- **Débitos 51xx**: Gastos de personal (salarios, parafiscales, provisiones)
- **Créditos 23xx-26xx**: Pasivos laborales (nómina por pagar, aportes, provisiones)

## Principios de arquitectura
- **Data-centric**: toda lógica de negocio en DB2 (triggers, constraints)
- **No display files**: interfaz 100% JSON/HTTP (sin pantallas 5250)
- **ILE**: service programs reutilizables con binding directories
- **MVC**: separación estricta datos/lógica/presentación
