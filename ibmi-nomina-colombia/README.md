# ibmi-nomina-colombia — Sistema de Nómina Quincenal Colombia

## Propósito
Liquidación quincenal de nómina conforme a la legislación laboral colombiana.
Integrado con `ibmi-company_system` (maestro de empleados) e `intERPrise` (contabilidad GL).

## Módulos del sistema

| Programa | Tipo | Función |
|----------|------|---------|
| `NOMCALCSR` | Service Program | Motor de cálculos — todas las fórmulas legales colombianas |
| `NOMLIQPGM` | Programa interactivo | Liquidación quincenal (pantalla 5250 subfile) |
| `NOMRPTPGM` | Programa interactivo | Comprobante de nómina al empleado |
| `NOMCONTPGM` | Programa batch | Contabilización en intERPrise GL via HTTP/JSON |
| `NOMLIQF` | Physical File | Almacena liquidaciones — clave: LIQNUM + LIQEMP |

## Flujo de proceso de negocio

```
ibmi-company_system           ibmi-nomina-colombia           intERPrise
     EMPLOYEE ────SQL──────> NOMLIQPGM ──NOMCALCSR──> NOMLIQF (LIQEST='L')
    (EMPNO, SALARY)          (liquidar)                     │
                                                       NOMCONTPGM
                                                       (HTTP/JSON POST)
                                                             │
                                                       GL Journal Entry
                                                       (LIQEST='C')
```

## Conceptos de nómina implementados

### Devengados (lo que recibe el empleado)
| Concepto | Fórmula | Procedimiento en NOMCALCSR |
|----------|---------|---------------------------|
| Salario quincenal | `SALARY / 30 * diasTrabajados` | `calcSalarioQuincena` |
| Auxilio transporte | `$162.000/mes` si salario ≤ 2 SMLV ($2.600.000) | `calcAuxTransporte` |
| Horas extras diurnas | `valorHora * 1.25` (Art. 168 CST) | `calcHorasExtras` |
| Horas extras nocturnas | `valorHora * 1.75` (Art. 168 CST) | `calcHorasExtras` |
| H.extras fest. diurnas | `valorHora * 1.75` (Art. 179 CST) | `calcHorasExtras` |
| H.extras fest. nocturnas | `valorHora * 2.10` (Art. 179 CST) | `calcHorasExtras` |
| Recargo nocturno | `valorHora * 1.35` (Art. 168 CST) | `calcHorasExtras` |

### Deducciones empleado
| Concepto | Fórmula | Norma | Procedimiento |
|----------|---------|-------|---------------|
| Salud empleado | `salario * 4%` | Ley 100/1993 Art.204 | `calcSaludEmpleado` |
| Pensión empleado | `salario * 4%` | Ley 100/1993 Art.20 | `calcPensionEmpleado` |
| Retención en la fuente | Tabla progresiva UVT 2024 (Art. 383 E.T.) | `calcRetencion` |

### Aportes patronales (costo adicional empleador)
| Concepto | Tasa | Norma | Procedimiento |
|----------|------|-------|---------------|
| Salud patronal | 8.5% | Ley 100/1993 | `calcSaludPatronal` |
| Pensión patronal | 12% | Ley 100/1993 | `calcPensionPatronal` |
| ARL | 0.522%–6.96% según nivel riesgo | Decreto 1607/2002 | `calcARL` |
| SENA | 2% | Ley 119/1994 | `calcSENA` |
| ICBF | 3% | Ley 7/1979 | `calcICBF` |
| Caja de compensación | 4% | Ley 21/1982 | `calcCaja` |

### Provisiones (pasivos diferidos)
| Concepto | Fórmula | Norma | Procedimiento |
|----------|---------|-------|---------------|
| Cesantías | `salario * dias / 360` | Art. 249 CST | `calcCesantias` |
| Intereses cesantías | `cesantias * 12% * dias / 360` | Ley 50/1990 Art.99 | `calcIntCesantias` |
| Prima de servicios | `salario * dias / 360` | Art. 306 CST | `calcPrima` |
| Vacaciones | `salario * dias / 720` | Art. 186 CST | `calcVacaciones` |

## Integración con company_system
- `NOMLIQPGM` lee `CMPSYS.EMPLOYEE` via SQL cross-library
- Clave compartida: `EMPLOYEE.EMPNO` = `NOMLIQF.LIQEMP` (ambos CHAR(6))
- Campos usados: `SALARY` (base de todos los cálculos), `HIREDATE` (antigüedad), `JOB` (nivel riesgo ARL)

## Integración con intERPrise
- `NOMCONTPGM` hace HTTP POST a `org.i-nterprise.transport.services`
- Genera asiento PUC Colombia: DB 51xx (gastos) / CR 23xx-26xx (pasivos)
- Estado de liquidación: `P`=Pendiente → `L`=Liquidada → `C`=Contabilizada

## Utilidades de IBM-i-RPG-Free-CLP-Code usadas
| Utilidad | Dónde se usa | Propósito |
|----------|-------------|-----------|
| `DATE_UDF` | `NOMCALCSR` / `NOMLIQPGM` | Calcular días exactos entre fechas para cesantías |
| `DATEADJ` | `NOMLIQPGM.srCalcFechasPeriodo` | Derivar último día del mes del período |
| `SQL_SKELETON` | `NOMCONTPGM` | Patrón cursor + manejo errores SQL batch |
| `USPS_Address` (patrón HTTP) | `NOMCONTPGM.srPostToIntERPrise` | HTTP POST via QSYS2.HTTP_POST |
| `RcdLckDsp` | `NOMLIQPGM.srGuardar` | Prevenir doble liquidación del mismo período |
| `Printing` | `NOMRPTPGM` | Comprobante impreso sin printer file externo |
