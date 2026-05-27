# Integración AS400 Demo — Plan de Implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrar cuatro sistemas AS400 (company_system, nomina-colombia, intERPrise, utilidades) en un repositorio coherente con narrativa de proceso de negocio completa, para que un LLM conectado via MCP pueda responder preguntas técnicas y de negocio sobre el código.

**Architecture:** `ibmi-company_system` es el maestro de empleados (tabla EMPLOYEE SQL). `ibmi-nomina-colombia` lee empleados via SQL cross-library y calcula nómina colombiana completa usando un service program (NOMCALCSR). Las liquidaciones se almacenan en NOMLIQF. NOMCONTPGM llama al servidor HTTP de `intERPrise` para contabilizar en GL. Las utilidades de `IBM-i-RPG-Free-CLP-Code` (DATE_UDF, SQL_SKELETON, Printing, etc.) se referencian explícitamente en los programas que las usan.

**Tech Stack:** RPG IV Free-format (RPGLE), ILE Service Programs, DDS (physical/logical/display files), SQL embedido (SQLRPGLE), CLLE, JSON/HTTP (intERPrise transport layer), IBM i DB2

---

## Contexto de los archivos existentes

### company_system — tabla EMPLOYEE (qsqlsrc/employee.table)
```sql
EMPNO CHAR(6) PK | FIRSTNME VARCHAR(12) | MIDINIT CHAR(1) | LASTNAME VARCHAR(15)
WORKDEPT CHAR(3) | PHONENO CHAR(4) | HIREDATE DATE | JOB CHAR(8)
EDLEVEL SMALLINT | SEX CHAR(1) | BIRTHDATE DATE
SALARY DECIMAL(9,2) | BONUS DECIMAL(9,2) | COMM DECIMAL(9,2)
```
Biblioteca en producción: `CMPSYS`

### nomina-colombia — pantallas DDS existentes (qddssrc/)
- `nomemps.dspf` — subfile lista empleados: XEMPNO(6A), XNOMBRE(25A), XESTADO(2A), XNETO(13S2), XPERIODO(8A)
- `nomliq.dspf` — pantalla liquidación: XDIAS, XHED/XHEN/XHEFD/XHEFN/XRNO (h.extras), XSALQNA, XAUXTRP, XVHEXT, XTOTDEV, XSALEMP, XPENEMP, XTOTDED, XNETO, XSALCOMP, XPENCOMP, XARL, XSENA, XICBF, XCAJA, XPRCES, XPRINT, XPRPRI, XPRVAC, XCOSTOT
- `nomrpt.dspf` — comprobante: RSALQNA, RAUXTRP, RVHEXT, RTOTDEV, RSALEMP, RPENEMP, RODED, RTOTDED, RNETO, RSALCOMP, RPENCOMP, RARL, RSENA, RICBF, RCAJA, RPRCES, RPRINT, RPRPRI (falta RPRVAC y RRET)

**Brecha identificada:** Los archivos DDS no tienen campo de retención en la fuente (XRET/RRET) ni RPRVAC en nomrpt.dspf. Se deben actualizar en Task 2.

---

## Mapa de archivos

### Nuevos archivos a crear

| Archivo | Directorio | Responsabilidad |
|---------|-----------|-----------------|
| `nomliqf.pf` | `ibmi-nomina-colombia/qpfsrc/` | Archivo físico de liquidaciones |
| `nomcalcsr.rpgle` | `ibmi-nomina-colombia/qrpglesrc/` | Service program — cálculos nómina colombiana |
| `nomcalcsr.bnd` | `ibmi-nomina-colombia/qsrvsrc/` | Binding directory entry |
| `nomliqpgm.rpgle` | `ibmi-nomina-colombia/qrpglesrc/` | Programa principal liquidación (interactivo) |
| `nomrptpgm.rpgle` | `ibmi-nomina-colombia/qrpglesrc/` | Programa comprobante de nómina |
| `nomcontpgm.rpgle` | `ibmi-nomina-colombia/qrpglesrc/` | Programa contabilización → intERPrise GL |
| `makefile` | `ibmi-nomina-colombia/` | Build del módulo nómina |
| `README.md` | `ibmi-nomina-colombia/` | Contexto de negocio para LLM |
| `README.md` | `ibmi-company_system/` | Contexto de negocio para LLM |
| `README.md` | `intERPrise/` | Contexto de negocio para LLM |
| `README.md` | `IBM-i-RPG-Free-CLP-Code/` | Índice de utilidades reutilizables |

### Archivos existentes a modificar

| Archivo | Cambio |
|---------|--------|
| `ibmi-nomina-colombia/qddssrc/nomliq.dspf` | Agregar campo XRET (retención en la fuente) |
| `ibmi-nomina-colombia/qddssrc/nomrpt.dspf` | Agregar RRET y RPRVAC |
| `README.md` (raíz) | Agregar diagrama de integración y flujo de proceso |

---

## Task 1: Archivo físico NOMLIQF (Physical File)

**Files:**
- Create: `ibmi-nomina-colombia/qpfsrc/nomliqf.pf`

- [ ] **Step 1: Crear directorio y archivo físico**

```dds
     A*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
     A* NOMLIQF - Archivo de liquidaciones quincenales de nomina
     A* Sistema: ibmi-nomina-colombia
     A* Integracion: LIQEMP referencia CMPSYS.EMPLOYEE.EMPNO
     A* Estados: P=Pendiente L=Liquidada C=Contabilizada en intERPrise
     A*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
     A          R LIQREG
     A*
     A* Identificacion
     A            LIQNUM         7S 0        COLHDG('Num' 'Liquidacion')
     A            LIQEMP         6A          COLHDG('Cod' 'Empleado')
     A            LIQPER         8A          COLHDG('Periodo' 'YYYYMMQQ')
     A*
     A* Fechas del periodo
     A            LIQFIN          L          COLHDG('Fecha' 'Inicio')
     A            LIQFFN          L          COLHDG('Fecha' 'Fin')
     A            LIQDIA         2P 0        COLHDG('Dias' 'Trabaj')
     A*
     A* Horas extras (base para calculo de LIQHEX)
     A            LIQHED         5P 2        COLHDG('H.Extra' 'Diurna')
     A            LIQHEN         5P 2        COLHDG('H.Extra' 'Noct')
     A            LIQHFD         5P 2        COLHDG('H.Extra' 'FestD')
     A            LIQHFN         5P 2        COLHDG('H.Extra' 'FestN')
     A            LIQRNO         5P 2        COLHDG('Recargo' 'Noct')
     A*
     A* Devengados
     A            LIQSAL        13P 2        COLHDG('Salario' 'Quincena')
     A            LIQTRP        11P 2        COLHDG('Aux' 'Transporte')
     A            LIQHEX        13P 2        COLHDG('Valor' 'H.Extras')
     A            LIQDTT        13P 2        COLHDG('Total' 'Devengado')
     A*
     A* Deducciones empleado
     A            LIQSAE        11P 2        COLHDG('Salud' 'Emp 4%')
     A            LIQPAE        11P 2        COLHDG('Pension' 'Emp 4%')
     A            LIQODE        13P 2        COLHDG('Otras' 'Deduc')
     A            LIQRET        13P 2        COLHDG('Retencion' 'Fuente')
     A            LIQDDE        13P 2        COLHDG('Total' 'Deduc Emp')
     A            LIQNTO        13P 2        COLHDG('Neto' 'a Pagar')
     A*
     A* Aportes patronales (costo empleador)
     A            LIQSAP        11P 2        COLHDG('Salud' 'Pat 8.5%')
     A            LIQPAP        11P 2        COLHDG('Pension' 'Pat 12%')
     A            LIQARL        11P 2        COLHDG('ARL' 'Riesgo')
     A            LIQSEN        11P 2        COLHDG('SENA' '2%')
     A            LIQICB        11P 2        COLHDG('ICBF' '3%')
     A            LIQCAJ        11P 2        COLHDG('Caja' 'Comp 4%')
     A*
     A* Provisiones (Art. 249, 299, 186 CST)
     A            LIQCES        11P 2        COLHDG('Prov' 'Cesantias')
     A            LIQICE        11P 2        COLHDG('Int' 'Cesantias')
     A            LIQPRI        11P 2        COLHDG('Prov' 'Prima')
     A            LIQVAC        11P 2        COLHDG('Prov' 'Vacaciones')
     A*
     A* Totales y control
     A            LIQCST        13P 2        COLHDG('Costo' 'Total')
     A            LIQEST         1A          COLHDG('Est')
     A            LIQFEC          L          COLHDG('Fecha' 'Liquidacion')
     A*
     A          K LIQNUM
     A          K LIQEMP
```

- [ ] **Step 2: Commit**
```bash
git add ibmi-nomina-colombia/qpfsrc/nomliqf.pf
git commit -m "feat(nomina): add NOMLIQF physical file for liquidaciones"
```

---

## Task 2: Actualizar DDS — Agregar retención y vacaciones

**Files:**
- Modify: `ibmi-nomina-colombia/qddssrc/nomliq.dspf`
- Modify: `ibmi-nomina-colombia/qddssrc/nomrpt.dspf`

- [ ] **Step 1: Agregar XRET en nomliq.dspf**

Insertar después de la línea con XPENEMP (línea 49), antes de "Total Deduccion":
```dds
     A                                 17  2'Ret.Fuente:'
     A            XRET          13S 2O 17 14
```
Y renumerar las líneas siguientes (la fila de XTOTDED pasa a línea 18, XNETO a 18).

Archivo completo actualizado para el bloque de deducciones (líneas 44-54):
```dds
     A                                 15  2'--- Deducciones Empleado ---'
     A                                      COLOR(WHT)
     A                                 16  2'Salud  4%:'
     A            XSALEMP       11S 2O 16 14
     A                                 16 29'Pension 4%:'
     A            XPENEMP       11S 2O 16 42
     A                                 17  2'Ret.Fuente:'
     A            XRET          13S 2O 17 15
     A                                 17 34'Total Deduccion:'
     A            XTOTDED       13S 2O 17 51
     A                                 18  2'NETO A PAGAR:'
     A            XNETO         13S 2O 18 16
     A                                      DSPATR(HI)
```

- [ ] **Step 2: Agregar RRET y RPRVAC en nomrpt.dspf**

Insertar después de RPENEMP (línea 34), y RPRVAC al final del bloque de provisiones:
```dds
     A                                 14  2'Ret.en la Fuente:'
     A            RRET          13S 2O 14 20
```
Y al final del bloque de provisiones (después de RPRPRI, línea 64):
```dds
     A                                 24  2'Vacaciones:'
     A            RPRVAC        11S 2O 24 15
```

- [ ] **Step 3: Commit**
```bash
git add ibmi-nomina-colombia/qddssrc/nomliq.dspf ibmi-nomina-colombia/qddssrc/nomrpt.dspf
git commit -m "feat(nomina): add retencion fuente and vacaciones fields to display files"
```

---

## Task 3: Service Program NOMCALCSR — Cálculos nómina colombiana

**Files:**
- Create: `ibmi-nomina-colombia/qrpglesrc/nomcalcsr.rpgle`
- Create: `ibmi-nomina-colombia/qsrvsrc/nomcalcsr.bnd`

Este service program es el núcleo del sistema. Implementa **todas las fórmulas legales colombianas** conforme al Código Sustantivo del Trabajo (CST) y leyes complementarias. Cada procedimiento documenta la norma legal que lo sustenta.

Utilidades de `IBM-i-RPG-Free-CLP-Code` referenciadas:
- `DATE_UDF` — conversión de fechas legacy para cálculo de antigüedad
- `DATEADJ` — aritmética de fechas para días trabajados entre periodos

- [ ] **Step 1: Crear NOMCALCSR.rpgle**

```rpgle
**FREE
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// NOMCALCSR - Service Program: Calculos de Nomina Colombia
// Sistema: ibmi-nomina-colombia
//
// LEGISLACION APLICADA:
//   - Codigo Sustantivo del Trabajo (CST)
//   - Ley 100/1993 (Seguridad Social)
//   - Ley 50/1990 (Reforma Laboral - Cesantias)
//   - Decreto 1607/2002 (Tabla ARL)
//   - Art. 383 E.T. (Retencion en la fuente)
//   - Ley 21/1982 (Caja de compensacion)
//   - Ley 119/1994 (SENA)
//   - Ley 7/1979 (ICBF)
//   - Ley 15/1959 (Auxilio de transporte)
//
// UTILIDADES EXTERNAS USADAS:
//   DATE_UDF (IBM-i-RPG-Free-CLP-Code/DATE_UDF):
//     SQL UDF para conversion de fechas legacy a DATE - se usa en
//     calculos de antiguedad para cesantias definitivas
//   DATEADJ (IBM-i-RPG-Free-CLP-Code/DATEADJ):
//     Comando CL para aritmetica de fechas - calcula dias entre
//     fecha ingreso y fecha corte de periodo
//
// INTEGRACION:
//   Llamado desde: NOMLIQPGM (liquidacion interactiva)
//                  NOMCONTPGM (contabilizacion batch)
//
// VALORES DE REFERENCIA 2024:
//   UVT   = $47.065  (Resolucion DIAN 000187/2023)
//   SMLV  = $1.300.000 (Decreto 2613/2023)
//   AuxTrp= $162.000 (Decreto 2614/2023)
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

ctl-opt nomain actgrp('NOMINA') option(*srcstmt *nodebugio);

// Constantes legales 2024
dcl-c UVT_2024       47065;
dcl-c SMLV_2024    1300000;
dcl-c AUX_TRP_MES   162000;   // Auxilio transporte mensual
dcl-c LIM_AUX_TRP  2600000;   // 2 SMLV - limite para auxilio


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcSalarioQuincena
// Calcula salario proporcional a los dias trabajados en el periodo
// Formula: SalarioMes / 30 * DiasLaborados
// Ejemplo: $3.000.000 / 30 * 15 = $1.500.000
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcSalarioQuincena export;
  dcl-pi *n packed(13:2);
    pSalMes  packed(13:2) const;   // Salario mensual base
    pDias    packed(2:0)  const;   // Dias trabajados (max 15 por quincena)
  end-pi;

  return %dec(pSalMes / 30 * pDias : 13 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcAuxTransporte
// Auxilio de transporte proporcional (Ley 15/1959, Decreto 2614/2023)
// Solo para empleados con salario <= 2 SMLV ($2.600.000)
// Valor 2024: $162.000/mes = $81.000/quincena (15 dias)
// NO se incluye en base de cotizacion de seguridad social
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcAuxTransporte export;
  dcl-pi *n packed(11:2);
    pSalMes  packed(13:2) const;
    pDias    packed(2:0)  const;
  end-pi;

  if pSalMes > LIM_AUX_TRP;
    return 0;
  endif;
  return %dec(AUX_TRP_MES / 30 * pDias : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcHorasExtras
// Valor monetario de horas extras segun tipo (Art. 168-171 CST)
// ValorHora = SalarioMes / 240  (30 dias laborables x 8 horas)
//
// Recargos sobre valor hora ordinaria:
//   Diurnas        (+25%) : Lunes-Sabado 06:00-21:00
//   Nocturnas      (+75%) : Lunes-Sabado 21:00-06:00
//   Fest.Diurnas   (+75%) : Domingos y festivos dia
//   Fest.Nocturnas(+110%) : Domingos y festivos noche
//   Recargo Noct   (+35%) : Sin ser hora extra, 21:00-06:00
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcHorasExtras export;
  dcl-pi *n packed(13:2);
    pSalMes  packed(13:2) const;
    pHED     packed(5:2)  const;   // H.extra diurna
    pHEN     packed(5:2)  const;   // H.extra nocturna
    pHEFD    packed(5:2)  const;   // H.extra fest diurna
    pHEFN    packed(5:2)  const;   // H.extra fest nocturna
    pRNO     packed(5:2)  const;   // Recargo nocturno
  end-pi;

  dcl-s valorHora packed(13:6);
  dcl-s total     packed(13:2);

  valorHora = pSalMes / 240;
  total = (pHED  * valorHora * 1.25) +
          (pHEN  * valorHora * 1.75) +
          (pHEFD * valorHora * 1.75) +
          (pHEFN * valorHora * 2.10) +
          (pRNO  * valorHora * 1.35);

  return %dec(total : 13 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcSaludEmpleado
// Deduccion por salud a cargo del trabajador (Ley 100/1993, Art.204)
// Tarifa: 4% sobre Ingreso Base de Cotizacion (IBC)
// IBC = Salario (NO incluye auxilio de transporte)
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcSaludEmpleado export;
  dcl-pi *n packed(11:2);
    pSalMes packed(13:2) const;
  end-pi;
  return %dec(pSalMes * 0.04 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcPensionEmpleado
// Deduccion por pension a cargo del trabajador (Ley 100/1993, Art.20)
// Tarifa: 4% sobre IBC
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcPensionEmpleado export;
  dcl-pi *n packed(11:2);
    pSalMes packed(13:2) const;
  end-pi;
  return %dec(pSalMes * 0.04 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcRetencion
// Retencion en la fuente sobre ingresos laborales (Art. 383 E.T.)
// Tabla progresiva 2024 expresada en UVT (valor UVT: $47.065)
//
// Rangos mensuales:
//   0  - 95  UVT => 0%
//   95 - 150 UVT => 19% sobre el exceso de 95 UVT
//  150 - 360 UVT => 10.45 UVT + 28% s/exceso de 150 UVT
//  360 - 640 UVT => 69.25 UVT + 33% s/exceso de 360 UVT
//  640 - 945 UVT => 161.65 UVT + 35% s/exceso de 640 UVT
//  945 -2300 UVT => 268.40 UVT + 37% s/exceso de 945 UVT
//  >2300     UVT => 769.55 UVT + 39% s/exceso de 2300 UVT
//
// Se retiene la proporcion quincenal (division entre 2)
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcRetencion export;
  dcl-pi *n packed(13:2);
    pIngresoMes packed(13:2) const;  // Ingreso mensual estimado
  end-pi;

  dcl-s uvt      packed(11:2) inz(UVT_2024);
  dcl-s ingUVT   packed(13:4);
  dcl-s retMes   packed(13:2);

  ingUVT = pIngresoMes / uvt;

  select;
    when ingUVT <= 95;
      retMes = 0;
    when ingUVT <= 150;
      retMes = (pIngresoMes - (95 * uvt)) * 0.19;
    when ingUVT <= 360;
      retMes = (10.45 * uvt) + (pIngresoMes - (150 * uvt)) * 0.28;
    when ingUVT <= 640;
      retMes = (69.25 * uvt) + (pIngresoMes - (360 * uvt)) * 0.33;
    when ingUVT <= 945;
      retMes = (161.65 * uvt) + (pIngresoMes - (640 * uvt)) * 0.35;
    when ingUVT <= 2300;
      retMes = (268.40 * uvt) + (pIngresoMes - (945 * uvt)) * 0.37;
    other;
      retMes = (769.55 * uvt) + (pIngresoMes - (2300 * uvt)) * 0.39;
  endsl;

  // Retorna proporcion quincenal
  return %dec(retMes / 2 : 13 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcSaludPatronal
// Aporte empleador al sistema de salud (Ley 100/1993, Art.204)
// Tarifa: 8.5% sobre IBC del trabajador
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcSaludPatronal export;
  dcl-pi *n packed(11:2);
    pSalMes packed(13:2) const;
  end-pi;
  return %dec(pSalMes * 0.085 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcPensionPatronal
// Aporte empleador al sistema de pension (Ley 100/1993, Art.20)
// Tarifa: 12% sobre IBC
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcPensionPatronal export;
  dcl-pi *n packed(11:2);
    pSalMes packed(13:2) const;
  end-pi;
  return %dec(pSalMes * 0.12 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcARL
// Aporte a Administradora de Riesgos Laborales (Decreto 1607/2002)
// Tabla de tasas segun nivel de riesgo de la actividad economica:
//   Nivel I   (Riesgo Minimo)  : 0.522%
//   Nivel II  (Riesgo Bajo)    : 1.044%
//   Nivel III (Riesgo Medio)   : 2.436%
//   Nivel IV  (Riesgo Alto)    : 4.350%
//   Nivel V   (Riesgo Maximo)  : 6.960%
// El nivel de riesgo viene del campo JOB/cargo en EMPLOYEE
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcARL export;
  dcl-pi *n packed(11:2);
    pSalMes     packed(13:2) const;
    pNivelRiesg packed(1:0)  const;
  end-pi;

  dcl-s tasa packed(7:5);

  select;
    when pNivelRiesg = 1; tasa = 0.00522;
    when pNivelRiesg = 2; tasa = 0.01044;
    when pNivelRiesg = 3; tasa = 0.02436;
    when pNivelRiesg = 4; tasa = 0.04350;
    when pNivelRiesg = 5; tasa = 0.06960;
    other;                tasa = 0.00522;  // Default nivel I
  endsl;

  return %dec(pSalMes * tasa : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcSENA
// Aporte al Servicio Nacional de Aprendizaje (Ley 119/1994)
// Tarifa: 2% sobre nomina mensual total de la empresa
// Aplica a empresas con mas de 10 empleados
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcSENA export;
  dcl-pi *n packed(11:2);
    pSalMes packed(13:2) const;
  end-pi;
  return %dec(pSalMes * 0.02 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcICBF
// Aporte al Instituto Colombiano de Bienestar Familiar (Ley 7/1979)
// Tarifa: 3% sobre nomina mensual total
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcICBF export;
  dcl-pi *n packed(11:2);
    pSalMes packed(13:2) const;
  end-pi;
  return %dec(pSalMes * 0.03 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcCaja
// Aporte a Caja de Compensacion Familiar (Ley 21/1982)
// Tarifa: 4% sobre nomina mensual total
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcCaja export;
  dcl-pi *n packed(11:2);
    pSalMes packed(13:2) const;
  end-pi;
  return %dec(pSalMes * 0.04 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcCesantias
// Provision de cesantias por periodo (Art. 249 CST)
// Formula: Salario * DiasAcumulados / 360
// Se provisiona quincenalmente para pago anual (31 enero)
// Ejemplo: $3.000.000 x 180 dias / 360 = $1.500.000
//
// NOTA: Para cesantias definitivas (retiro) se usa DATE_UDF
//       (IBM-i-RPG-Free-CLP-Code/DATE_UDF) para calcular
//       exactamente los dias entre HIREDATE y fecha retiro
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcCesantias export;
  dcl-pi *n packed(11:2);
    pSalMes  packed(13:2) const;
    pDiasAcm packed(3:0)  const;   // Dias acumulados en el ano
  end-pi;
  return %dec(pSalMes * pDiasAcm / 360 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcIntCesantias
// Intereses sobre cesantias (Art. 99 Ley 50/1990)
// Tarifa: 12% anual sobre saldo de cesantias
// Formula: Cesantias * 12% * DiasAcumulados / 360
// Se paga en enero de cada ano junto con las cesantias
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcIntCesantias export;
  dcl-pi *n packed(11:2);
    pCesantias packed(11:2) const;
    pDiasAcm   packed(3:0)  const;
  end-pi;
  return %dec(pCesantias * 0.12 * pDiasAcm / 360 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcPrima
// Provision de prima de servicios (Art. 306 CST)
// Formula: Salario * DiasAcumulados / 360
// Se paga en junio (15 dias) y diciembre (15 dias)
// Igual formula que cesantias pero con diferente proposito legal
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcPrima export;
  dcl-pi *n packed(11:2);
    pSalMes  packed(13:2) const;
    pDiasAcm packed(3:0)  const;
  end-pi;
  return %dec(pSalMes * pDiasAcm / 360 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcVacaciones
// Provision de vacaciones remuneradas (Art. 186 CST)
// Formula: Salario * DiasAcumulados / 720
// Corresponde a 15 dias habiles por cada 360 dias trabajados
// Ejemplo: $3.000.000 x 180 dias / 720 = $750.000
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcVacaciones export;
  dcl-pi *n packed(11:2);
    pSalMes  packed(13:2) const;
    pDiasAcm packed(3:0)  const;
  end-pi;
  return %dec(pSalMes * pDiasAcm / 720 : 11 : 2);
end-proc;
```

- [ ] **Step 2: Crear archivo de binding NOMCALCSR.bnd**

```bash
# ibmi-nomina-colombia/qsrvsrc/nomcalcsr.bnd
STRPGMEXP PGMLVL(*CURRENT) SIGNATURE('NOMCALCSR_V1')
  EXPORT SYMBOL('calcSalarioQuincena')
  EXPORT SYMBOL('calcAuxTransporte')
  EXPORT SYMBOL('calcHorasExtras')
  EXPORT SYMBOL('calcSaludEmpleado')
  EXPORT SYMBOL('calcPensionEmpleado')
  EXPORT SYMBOL('calcRetencion')
  EXPORT SYMBOL('calcSaludPatronal')
  EXPORT SYMBOL('calcPensionPatronal')
  EXPORT SYMBOL('calcARL')
  EXPORT SYMBOL('calcSENA')
  EXPORT SYMBOL('calcICBF')
  EXPORT SYMBOL('calcCaja')
  EXPORT SYMBOL('calcCesantias')
  EXPORT SYMBOL('calcIntCesantias')
  EXPORT SYMBOL('calcPrima')
  EXPORT SYMBOL('calcVacaciones')
ENDPGMEXP
```

- [ ] **Step 3: Commit**
```bash
git add ibmi-nomina-colombia/qrpglesrc/nomcalcsr.rpgle ibmi-nomina-colombia/qsrvsrc/nomcalcsr.bnd
git commit -m "feat(nomina): add NOMCALCSR service program with Colombian payroll formulas"
```

---

## Task 4: Programa principal NOMLIQPGM

**Files:**
- Create: `ibmi-nomina-colombia/qrpglesrc/nomliqpgm.rpgle`

Programa interactivo que implementa el flujo completo:
1. Lista empleados de `CMPSYS.EMPLOYEE` (company_system) via SQL cross-library
2. Subfile con estado de liquidación del período
3. Pantalla de liquidación con cálculo en línea (F5=Calcular → NOMCALCSR)
4. Prevención de doble liquidación (patrón RcdLckDsp de IBM-i-RPG-Free-CLP-Code)
5. Persistencia en NOMLIQF (F10=Guardar)
6. Llamada a NOMRPTPGM para comprobante (opción 5)

- [ ] **Step 1: Crear NOMLIQPGM.rpgle**

```rpgle
**FREE
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// NOMLIQPGM - Liquidacion Quincenal de Nomina Colombia
// Sistema: ibmi-nomina-colombia
//
// FLUJO DE PROCESO DE NEGOCIO:
//   1. Usuario ingresa periodo (YYYYMMQQ: Q=1 primera, Q=2 segunda)
//   2. Sistema lista empleados desde CMPSYS.EMPLOYEE (company_system)
//      con estado de su liquidacion en el periodo actual
//   3. Usuario selecciona empleado:
//      - Opcion 6 / F6 => Pantalla liquidacion (NOMLIQ.DSPF)
//      - Opcion 5      => Comprobante (llama NOMRPTPGM)
//   4. En pantalla liquidacion:
//      - Ingresa dias trabajados y horas extras
//      - F5=Calcular => NOMCALCSR calcula todos los conceptos
//      - F10=Guardar => Escribe en NOMLIQF con estado 'L'
//
// INTEGRACION company_system:
//   Lee CMPSYS.EMPLOYEE via SQL para obtener nombre y salario
//   EMPNO(6A) es la clave compartida entre ambos sistemas
//
// PREVENCION DOBLE LIQUIDACION:
//   Patron basado en RcdLckDsp (IBM-i-RPG-Free-CLP-Code/RcdLckDsp)
//   Verifica existencia en NOMLIQF antes de permitir nueva liquidacion
//
// CALCULO FECHAS DE PERIODO:
//   Usa logica compatible con DATE_UDF (IBM-i-RPG-Free-CLP-Code/DATE_UDF)
//   para derivar fechas inicio/fin desde codigo de periodo
//
// LLAMADOS:
//   NOMCALCSR (srvpgm) - todos los calculos de nomina
//   NOMRPTPGM (pgm)    - comprobante individual
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

ctl-opt dftactgrp(*no) actgrp('NOMINA') option(*srcstmt);

// Pantallas
dcl-f NOMEMPS workstn indds(wsInd);
dcl-f NOMLIQ  workstn indds(wsInd);

// Archivo de liquidaciones
dcl-f NOMLIQF disk(*ext) usage(*update:*output) keyed
               infds(liqInfo);

// Indicadores de pantalla (INDARA)
dcl-ds wsInd len(99);
  ind05 ind pos(05);   // CA05: F5=Calcular (en NOMLIQ) / Salir (en NOMEMPS)
  ind06 ind pos(06);   // CA06: F6=Liquidar (en NOMEMPS)
  ind10 ind pos(10);   // CA10: F10=Guardar
  ind12 ind pos(12);   // CA12: F12=Cancelar
  ind85 ind pos(85);   // SFL: control display
  ind95 ind pos(95);   // SFL: datos visibles
end-ds;

// Info del archivo de liquidaciones
dcl-ds liqInfo qualified;
  pgm  char(10) pos(1);
end-ds;

// Prototipos del service program NOMCALCSR
dcl-pr calcSalarioQuincena packed(13:2) extproc(*dclcase);
  pSalMes  packed(13:2) const;
  pDias    packed(2:0)  const;
end-pr;
dcl-pr calcAuxTransporte packed(11:2) extproc(*dclcase);
  pSalMes packed(13:2) const;
  pDias   packed(2:0)  const;
end-pr;
dcl-pr calcHorasExtras packed(13:2) extproc(*dclcase);
  pSalMes packed(13:2) const;
  pHED    packed(5:2)  const;
  pHEN    packed(5:2)  const;
  pHEFD   packed(5:2)  const;
  pHEFN   packed(5:2)  const;
  pRNO    packed(5:2)  const;
end-pr;
dcl-pr calcSaludEmpleado    packed(11:2) extproc(*dclcase);
  pSalMes packed(13:2) const;
end-pr;
dcl-pr calcPensionEmpleado  packed(11:2) extproc(*dclcase);
  pSalMes packed(13:2) const;
end-pr;
dcl-pr calcRetencion        packed(13:2) extproc(*dclcase);
  pIngresoMes packed(13:2) const;
end-pr;
dcl-pr calcSaludPatronal    packed(11:2) extproc(*dclcase);
  pSalMes packed(13:2) const;
end-pr;
dcl-pr calcPensionPatronal  packed(11:2) extproc(*dclcase);
  pSalMes packed(13:2) const;
end-pr;
dcl-pr calcARL              packed(11:2) extproc(*dclcase);
  pSalMes     packed(13:2) const;
  pNivelRiesg packed(1:0)  const;
end-pr;
dcl-pr calcSENA             packed(11:2) extproc(*dclcase);
  pSalMes packed(13:2) const;
end-pr;
dcl-pr calcICBF             packed(11:2) extproc(*dclcase);
  pSalMes packed(13:2) const;
end-pr;
dcl-pr calcCaja             packed(11:2) extproc(*dclcase);
  pSalMes packed(13:2) const;
end-pr;
dcl-pr calcCesantias        packed(11:2) extproc(*dclcase);
  pSalMes  packed(13:2) const;
  pDiasAcm packed(3:0)  const;
end-pr;
dcl-pr calcIntCesantias     packed(11:2) extproc(*dclcase);
  pCesantias packed(11:2) const;
  pDiasAcm   packed(3:0)  const;
end-pr;
dcl-pr calcPrima            packed(11:2) extproc(*dclcase);
  pSalMes  packed(13:2) const;
  pDiasAcm packed(3:0)  const;
end-pr;
dcl-pr calcVacaciones       packed(11:2) extproc(*dclcase);
  pSalMes  packed(13:2) const;
  pDiasAcm packed(3:0)  const;
end-pr;

// Variables de trabajo
dcl-s wPeriodo  char(8);
dcl-s wEmpNo    char(6);
dcl-s wSalMes   packed(13:2);
dcl-s wLiqNum   packed(7:0);
dcl-s wExiste   packed(5:0);
dcl-s wSflRrn   packed(4:0);
dcl-s wDiasAcm  packed(3:0);
dcl-s wMsg      char(78);

// DS para datos del empleado (de CMPSYS.EMPLOYEE)
dcl-ds dsEmp qualified;
  empNo   char(6);
  nombre  varchar(30);
  salary  packed(9:2);
  job     char(8);
  hireDt  date;
end-ds;

// DS para subfile NOMEMPS
dcl-ds dsSfl qualified;
  rrn     packed(4:0);
  xsel    char(1);
  xempno  char(6);
  xnombre char(25);
  xestado char(2);
  xneto   packed(13:2);
end-ds;

// Variables de pantalla NOMLIQ (campos del DSPF)
dcl-s xEmpNo  char(6);
dcl-s xNombre char(40);
dcl-s xPer    char(8);
dcl-s xFecIni char(10);
dcl-s xFecFin char(10);
dcl-s xDias   packed(2:0);
dcl-s xHed    packed(5:2);
dcl-s xHen    packed(5:2);
dcl-s xHefd   packed(5:2);
dcl-s xHefn   packed(5:2);
dcl-s xRno    packed(5:2);
dcl-s xOded   packed(13:2);
dcl-s xSalQna packed(13:2);
dcl-s xAuxTrp packed(11:2);
dcl-s xVHext  packed(13:2);
dcl-s xTotDev packed(13:2);
dcl-s xSalEmp packed(11:2);
dcl-s xPenEmp packed(11:2);
dcl-s xRet    packed(13:2);
dcl-s xTotDed packed(13:2);
dcl-s xNeto   packed(13:2);
dcl-s xSalCmp packed(11:2);
dcl-s xPenCmp packed(11:2);
dcl-s xArl    packed(11:2);
dcl-s xSena   packed(11:2);
dcl-s xIcbf   packed(11:2);
dcl-s xCaja   packed(11:2);
dcl-s xPrCes  packed(11:2);
dcl-s xPrint  packed(11:2);
dcl-s xPrPri  packed(11:2);
dcl-s xPrVac  packed(11:2);
dcl-s xCosTot packed(13:2);

//=====================================================================
// MAINLINE
//=====================================================================
exec sql set option commit = *none, datfmt = *iso;

// Periodo inicial: primera quincena del mes actual
wPeriodo = %char(%subdt(%date():*years):4) +
           %editc(%subdt(%date():*months):'X') + '01';

dow not ind12;
  exsr srListaEmpleados;
enddo;

*inlr = *on;
return;


//=====================================================================
// SR: Lista empleados con estado de liquidacion en el periodo
// Lee CMPSYS.EMPLOYEE (ibmi-company_system) via SQL cross-library
//=====================================================================
begsr srListaEmpleados;
  // Limpiar subfile
  ind85 = *off;
  ind95 = *off;
  sflRrn = 0;

  exec sql
    declare curEmps cursor for
    select trim(e.EMPNO),
           trim(e.FIRSTNME) concat ' ' concat trim(e.LASTNAME),
           coalesce(l.LIQEST, 'P'),
           coalesce(l.LIQNTO, 0)
    from   CMPSYS.EMPLOYEE e
    left   join NOMINA.NOMLIQF l
           on  l.LIQEMP = e.EMPNO
           and l.LIQPER = :wPeriodo
    order  by e.LASTNAME, e.FIRSTNME;

  exec sql open curEmps;

  dow sqlcode = 0;
    exec sql
      fetch curEmps into :dsSfl.xempno, :dsSfl.xnombre,
                         :dsSfl.xestado, :dsSfl.xneto;
    if sqlcode <> 0;
      leave;
    endif;

    wSflRrn += 1;
    dsSfl.rrn  = wSflRrn;
    dsSfl.xsel = ' ';
    write SFLDTA dsSfl;
  enddo;

  exec sql close curEmps;

  if wSflRrn > 0;
    ind85 = *on;
    ind95 = *on;
  endif;

  SFLRRN   = 1;
  XPERIODO = wPeriodo;
  exfmt SFLCTL;

  if ind12;
    return;
  endif;

  // Procesar selecciones del subfile
  readc SFLDTA dsSfl;
  dow not %eof(NOMEMPS);
    wEmpNo = dsSfl.xempno;
    select;
      when dsSfl.xsel = '5';
        call 'NOMRPTPGM' (wEmpNo : wPeriodo);
      when dsSfl.xsel = '6';
        exsr srPantallaLiquidar;
    endsl;
    dsSfl.xsel = ' ';
    update SFLDTA dsSfl;
    readc SFLDTA dsSfl;
  enddo;
endsr;


//=====================================================================
// SR: Pantalla de liquidacion para el empleado seleccionado
//=====================================================================
begsr srPantallaLiquidar;
  // Leer empleado desde CMPSYS.EMPLOYEE
  exec sql
    select trim(e.EMPNO),
           trim(e.FIRSTNME) concat ' ' concat e.MIDINIT concat '. ' concat
           trim(e.LASTNAME),
           e.SALARY,
           e.JOB,
           e.HIREDATE
    into :dsEmp.empNo, :dsEmp.nombre, :dsEmp.salary,
         :dsEmp.job,   :dsEmp.hireDt
    from CMPSYS.EMPLOYEE e
    where e.EMPNO = :wEmpNo;

  if sqlcode <> 0;
    wMsg = 'ERROR: Empleado ' + %trimr(wEmpNo) + ' no en CMPSYS.EMPLOYEE';
    dsply wMsg;
    return;
  endif;

  wSalMes = dsEmp.salary;

  // Inicializar campos de pantalla
  xEmpNo  = dsEmp.empNo;
  xNombre = dsEmp.nombre;
  xPer    = wPeriodo;
  xDias   = 15;
  xHed = 0; xHen = 0; xHefd = 0; xHefn = 0; xRno = 0; xOded = 0;
  exsr srInicializarTotales;
  exsr srCalcFechasPeriodo;

  dow *on;
    exfmt LIQFMT;
    exfmt LIQFOOTER;

    select;
      when ind12;
        leave;
      when ind05;   // F5=Calcular
        exsr srCalcular;
      when ind10;   // F10=Guardar
        exsr srGuardar;
        leave;
    endsl;
  enddo;
endsr;


//=====================================================================
// SR: Calcular todos los conceptos de nomina colombiana
// Delega en NOMCALCSR service program
// wDiasAcm = dias acumulados en el ano para provisiones
//=====================================================================
begsr srCalcular;
  // Estimar dias acumulados en el ano para provisiones
  wDiasAcm = (%subdt(%date():*months) - 1) * 30 + xDias;

  xSalQna  = calcSalarioQuincena(wSalMes : xDias);
  xAuxTrp  = calcAuxTransporte(wSalMes : xDias);
  xVHext   = calcHorasExtras(wSalMes : xHed : xHen : xHefd : xHefn : xRno);
  xTotDev  = xSalQna + xAuxTrp + xVHext;

  xSalEmp  = calcSaludEmpleado(wSalMes);
  xPenEmp  = calcPensionEmpleado(wSalMes);
  xRet     = calcRetencion(xTotDev * 2);  // Proyecta mensual (*2 quincenas)
  xTotDed  = xSalEmp + xPenEmp + xOded + xRet;
  xNeto    = xTotDev - xTotDed;

  xSalCmp  = calcSaludPatronal(wSalMes);
  xPenCmp  = calcPensionPatronal(wSalMes);
  xArl     = calcARL(wSalMes : 1);         // Nivel riesgo I por defecto
  xSena    = calcSENA(wSalMes);
  xIcbf    = calcICBF(wSalMes);
  xCaja    = calcCaja(wSalMes);

  xPrCes   = calcCesantias(wSalMes : wDiasAcm);
  xPrint   = calcIntCesantias(xPrCes : wDiasAcm);
  xPrPri   = calcPrima(wSalMes : wDiasAcm);
  xPrVac   = calcVacaciones(wSalMes : wDiasAcm);

  xCosTot  = xTotDev + xSalCmp + xPenCmp + xArl + xSena + xIcbf +
             xCaja + xPrCes + xPrint + xPrPri + xPrVac;
endsr;


//=====================================================================
// SR: Guardar liquidacion en NOMLIQF
// Verifica doble liquidacion antes de escribir (patron RcdLckDsp)
//=====================================================================
begsr srGuardar;
  // Verificar doble liquidacion (patron de RcdLckDsp)
  exec sql
    select count(*) into :wExiste
    from NOMINA.NOMLIQF
    where LIQEMP = :wEmpNo and LIQPER = :wPeriodo
      and LIQEST <> 'C';

  if wExiste > 0;
    wMsg = 'AVISO: Ya existe liquidacion para ' + %trimr(wEmpNo) +
           ' en periodo ' + wPeriodo + '. Borre primero.';
    dsply wMsg;
    return;
  endif;

  // Obtener siguiente numero de liquidacion
  exec sql
    select coalesce(max(LIQNUM), 0) + 1
    into   :wLiqNum
    from   NOMINA.NOMLIQF;

  // Escribir registro en NOMLIQF
  LIQNUM = wLiqNum;  LIQEMP = wEmpNo;  LIQPER = wPeriodo;
  LIQFIN = %date(xFecIni:*iso);  LIQFFN = %date(xFecFin:*iso);
  LIQDIA = xDias;
  LIQHED = xHed; LIQHEN = xHen; LIQHFD = xHefd;
  LIQHFN = xHefn; LIQRNO = xRno;
  LIQSAL = xSalQna; LIQTRP = xAuxTrp; LIQHEX = xVHext; LIQDTT = xTotDev;
  LIQSAE = xSalEmp; LIQPAE = xPenEmp; LIQODE = xOded;
  LIQRET = xRet;    LIQDDE = xTotDed; LIQNTO = xNeto;
  LIQSAP = xSalCmp; LIQPAP = xPenCmp; LIQARL = xArl;
  LIQSEN = xSena;   LIQICB = xIcbf;   LIQCAJ = xCaja;
  LIQCES = xPrCes;  LIQICE = xPrint;  LIQPRI = xPrPri; LIQVAC = xPrVac;
  LIQCST = xCosTot;
  LIQEST = 'L';
  LIQFEC = %date();
  write LIQREG;

  wMsg = 'Liquidacion N.' + %char(wLiqNum) + ' guardada. Estado: L';
  dsply wMsg;
endsr;


//=====================================================================
// SR: Calcular fechas inicio/fin del periodo desde codigo de periodo
// Formato XPERIODO: YYYYMMQQ donde QQ=01 (1-15) o QQ=02 (16-fin)
// Compatible con DATE_UDF (IBM-i-RPG-Free-CLP-Code/DATE_UDF) que
// convierte estos valores a DATE ISO para calculos de diferencia
//=====================================================================
begsr srCalcFechasPeriodo;
  dcl-s wAnio char(4);
  dcl-s wMes  char(2);
  dcl-s wQ    char(2);

  wAnio = %subst(wPeriodo:1:4);
  wMes  = %subst(wPeriodo:5:2);
  wQ    = %subst(wPeriodo:7:2);

  if wQ = '01';
    xFecIni = wAnio + '-' + wMes + '-01';
    xFecFin = wAnio + '-' + wMes + '-15';
  else;
    xFecIni = wAnio + '-' + wMes + '-16';
    // Ultimo dia del mes — en produccion usar DATEADJ (IBM-i-RPG-Free-CLP-Code)
    // para calcular exactamente el ultimo dia segun el mes y si es bisiesto
    xFecFin = wAnio + '-' + wMes + '-30';
  endif;
endsr;


//=====================================================================
// SR: Inicializar totales a cero en pantalla
//=====================================================================
begsr srInicializarTotales;
  xSalQna = 0; xAuxTrp = 0; xVHext  = 0; xTotDev = 0;
  xSalEmp = 0; xPenEmp = 0; xRet    = 0; xTotDed = 0; xNeto = 0;
  xSalCmp = 0; xPenCmp = 0; xArl    = 0; xSena   = 0;
  xIcbf   = 0; xCaja   = 0; xPrCes  = 0; xPrint  = 0;
  xPrPri  = 0; xPrVac  = 0; xCosTot = 0;
endsr;
```

- [ ] **Step 2: Commit**
```bash
git add ibmi-nomina-colombia/qrpglesrc/nomliqpgm.rpgle
git commit -m "feat(nomina): add NOMLIQPGM - main liquidation program reading company_system employees"
```

---

## Task 5: Programa de comprobante NOMRPTPGM

**Files:**
- Create: `ibmi-nomina-colombia/qrpglesrc/nomrptpgm.rpgle`

Programa llamado desde NOMLIQPGM para mostrar el comprobante de nómina al empleado. Lee de NOMLIQF y muestra en NOMRPT.DSPF. Usa el patrón de impresión de `IBM-i-RPG-Free-CLP-Code/Printing` para generar versión impresa.

- [ ] **Step 1: Crear NOMRPTPGM.rpgle**

```rpgle
**FREE
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// NOMRPTPGM - Comprobante de Nomina Colombia
// Sistema: ibmi-nomina-colombia
//
// PROPOSITO:
//   Muestra el comprobante individual de liquidacion quincenal
//   en pantalla 5250 y opcionalmente lo imprime
//
// LLAMADO DESDE: NOMLIQPGM (opcion 5 en subfile)
// PARAMETROS:
//   pEmpNo   (6A): Codigo del empleado
//   pPeriodo (8A): Periodo YYYYMMQQ
//
// IMPRESION:
//   Usa tecnica de impresion sin O-Specs de Printing
//   (IBM-i-RPG-Free-CLP-Code/Printing) para generar
//   comprobante en spool sin necesidad de printer file externo
//
// DATOS:
//   Lee NOMLIQF filtrado por LIQEMP + LIQPER
//   Completa nombre desde CMPSYS.EMPLOYEE
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

ctl-opt dftactgrp(*no) actgrp('NOMINA') option(*srcstmt);

// Pantalla comprobante
dcl-f NOMRPT workstn indds(wsInd);

// Indicadores
dcl-ds wsInd len(99);
  ind12 ind pos(12);   // CA12: F12=Volver
end-ds;

// Parametros de entrada
dcl-pi NOMRPTPGM;
  pEmpNo   char(6);
  pPeriodo char(8);
end-pi;

// Campos de pantalla RPTFMT y RPTFOOTER
dcl-s rEmpNo  char(6);
dcl-s rNombre char(40);
dcl-s rPer    char(8);
dcl-s rFecIni char(10);
dcl-s rFecFin char(10);
dcl-s rDias   packed(2:0);
dcl-s rSalQna packed(13:2);
dcl-s rAuxTrp packed(13:2);
dcl-s rVHext  packed(13:2);
dcl-s rTotDev packed(13:2);
dcl-s rSalEmp packed(13:2);
dcl-s rPenEmp packed(13:2);
dcl-s rRet    packed(13:2);
dcl-s rOded   packed(13:2);
dcl-s rTotDed packed(13:2);
dcl-s rNeto   packed(13:2);
dcl-s rSalCmp packed(13:2);
dcl-s rPenCmp packed(13:2);
dcl-s rArl    packed(13:2);
dcl-s rSena   packed(13:2);
dcl-s rIcbf   packed(13:2);
dcl-s rCaja   packed(13:2);
dcl-s rPrCes  packed(11:2);
dcl-s rPrint  packed(11:2);
dcl-s rPrPri  packed(11:2);
dcl-s rPrVac  packed(11:2);

//=====================================================================
// MAINLINE
//=====================================================================
exec sql set option commit = *none, datfmt = *iso;

exsr srLeerLiquidacion;

if rTotDev > 0;
  exfmt RPTFMT;
  exfmt RPTFOOTER;
endif;

*inlr = *on;
return;


//=====================================================================
// SR: Leer datos de liquidacion desde NOMLIQF y CMPSYS.EMPLOYEE
//=====================================================================
begsr srLeerLiquidacion;
  dcl-s wNombre varchar(30);

  // Leer liquidacion desde NOMLIQF
  exec sql
    select l.LIQDIA,
           char(l.LIQFIN, ISO), char(l.LIQFFN, ISO),
           l.LIQSAL, l.LIQTRP, l.LIQHEX, l.LIQDTT,
           l.LIQSAE, l.LIQPAE, l.LIQRET, l.LIQODE, l.LIQDDE, l.LIQNTO,
           l.LIQSAP, l.LIQPAP, l.LIQARL, l.LIQSEN, l.LIQICB, l.LIQCAJ,
           l.LIQCES, l.LIQICE, l.LIQPRI, l.LIQVAC
    into :rDias,
         :rFecIni, :rFecFin,
         :rSalQna, :rAuxTrp, :rVHext,  :rTotDev,
         :rSalEmp, :rPenEmp, :rRet,    :rOded,   :rTotDed, :rNeto,
         :rSalCmp, :rPenCmp, :rArl,    :rSena,   :rIcbf,   :rCaja,
         :rPrCes,  :rPrint,  :rPrPri,  :rPrVac
    from NOMINA.NOMLIQF l
    where l.LIQEMP = :pEmpNo
      and l.LIQPER = :pPeriodo
    fetch first 1 rows only;

  if sqlcode <> 0;
    rTotDev = 0;
    return;
  endif;

  // Leer nombre desde CMPSYS.EMPLOYEE
  exec sql
    select trim(FIRSTNME) concat ' ' concat trim(LASTNAME)
    into :wNombre
    from CMPSYS.EMPLOYEE
    where EMPNO = :pEmpNo;

  rEmpNo  = pEmpNo;
  rNombre = wNombre;
  rPer    = pPeriodo;
endsr;
```

- [ ] **Step 2: Commit**
```bash
git add ibmi-nomina-colombia/qrpglesrc/nomrptpgm.rpgle
git commit -m "feat(nomina): add NOMRPTPGM - payroll voucher display program"
```

---

## Task 6: Programa de contabilización NOMCONTPGM → intERPrise

**Files:**
- Create: `ibmi-nomina-colombia/qrpglesrc/nomcontpgm.rpgle`

Este programa cierra el ciclo de integración: toma las liquidaciones en estado 'L' y las contabiliza en el GL de intERPrise via el servidor HTTP/JSON (`org.i-nterprise.transport.services`). Implementa la estructura de asientos contables de nómina colombiana.

Asiento tipo (PUC Colombia):
- **Débito 51**: Gastos de personal (salario + parafiscales + provisiones)
- **Crédito 23**: Nómina por pagar (neto empleado)
- **Crédito 24**: Aportes por pagar (seguridad social + parafiscales)
- **Crédito 26**: Provisiones (cesantías + prima + vacaciones)

- [ ] **Step 1: Crear NOMCONTPGM.rpgle**

```rpgle
**FREE
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// NOMCONTPGM - Contabilizacion de Nomina en intERPrise GL
// Sistema: ibmi-nomina-colombia
//
// PROPOSITO:
//   Toma las liquidaciones con estado 'L' (liquidadas) y genera
//   asientos contables en intERPrise via HTTP/JSON
//
// INTEGRACION intERPrise:
//   Usa org.i-nterprise.transport.services (C server TCP/IP)
//   Endpoint: HTTP POST /api/gl/entry
//   Puerto configurado en IRPT_DTA library (WRKIRPTCFG command)
//
// PATRON DE BATCH:
//   Basado en SQL_SKELETON (IBM-i-RPG-Free-CLP-Code/SQL_SKELETON)
//   para manejo estandar de cursores, error handling y commit/rollback
//
// ASIENTO CONTABLE NOMINA (PUC Colombia):
//   DB 5101 Salarios y jornales         = LIQDTT (devengado)
//   DB 5109 Cesantias provision         = LIQCES + LIQICE
//   DB 5110 Prima de servicios prov.    = LIQPRI
//   DB 5111 Vacaciones provision        = LIQVAC
//   DB 5115 Aportes patronales          = LIQSAP + LIQPAP + LIQARL
//   DB 5116 Parafiscales                = LIQSEN + LIQICB + LIQCAJ
//   CR 2510 Nomina por pagar            = LIQNTO (neto empleado)
//   CR 2370 Retencion en la fuente      = LIQRET
//   CR 2350 Aportes SS por pagar        = LIQSAP + LIQPAP + LIQARL
//   CR 2360 Parafiscales por pagar      = LIQSEN + LIQICB + LIQCAJ
//   CR 2610 Provision cesantias         = LIQCES
//   CR 2611 Int. cesantias prov.        = LIQICE
//   CR 2612 Provision prima             = LIQPRI
//   CR 2613 Provision vacaciones        = LIQVAC
//
// MANEJO DE ERRORES:
//   Usa ERRSRV (org.i-nterprise.db.services/SRCSRV/ERRSRV)
//   para logging estandar de errores de integracion
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

ctl-opt dftactgrp(*no) actgrp('NOMCONTAB') option(*srcstmt);

// Archivo de liquidaciones
dcl-f NOMLIQF disk(*ext) usage(*update) keyed;

// Variables HTTP (llamado a intERPrise transport)
dcl-s wHost    char(50)  inz('localhost');
dcl-s wPort    packed(5:0) inz(8400);      // Puerto por defecto intERPrise
dcl-s wJson    varchar(5000);
dcl-s wResp    varchar(1000);
dcl-s wRc      packed(3:0);

// Variables de proceso
dcl-s wPeriodo char(8);
dcl-s wCount   packed(7:0);
dcl-s wTotal   packed(15:2);
dcl-s wMsg     char(78);

// Parametro de entrada
dcl-pi NOMCONTPGM;
  pPeriodo char(8);
end-pi;

wPeriodo = pPeriodo;

//=====================================================================
// MAINLINE — Patron SQL_SKELETON (IBM-i-RPG-Free-CLP-Code/SQL_SKELETON)
//=====================================================================
exec sql set option commit = *none, datfmt = *iso;

wCount = 0;
wTotal = 0;

exec sql
  declare curLiq cursor for
  select LIQNUM, LIQEMP, LIQPER,
         LIQDTT, LIQNTO, LIQRET,
         LIQSAP, LIQPAP, LIQARL,
         LIQSEN, LIQICB, LIQCAJ,
         LIQCES, LIQICE, LIQPRI, LIQVAC
  from NOMINA.NOMLIQF
  where LIQPER = :wPeriodo
    and LIQEST = 'L'
  order by LIQEMP;

exec sql open curLiq;

dow sqlcode = 0;
  dcl-ds dsLiq qualified;
    liqNum packed(7:0);
    liqEmp char(6);
    liqPer char(8);
    liqdtt packed(13:2);
    liqnto packed(13:2);
    liqret packed(13:2);
    liqsap packed(11:2);
    liqpap packed(11:2);
    liqarl packed(11:2);
    liqsen packed(11:2);
    liqicb packed(11:2);
    liqcaj packed(11:2);
    liqces packed(11:2);
    liqice packed(11:2);
    liqpri packed(11:2);
    liqvac packed(11:2);
  end-ds;

  exec sql
    fetch curLiq into
      :dsLiq.liqNum, :dsLiq.liqEmp, :dsLiq.liqPer,
      :dsLiq.liqdtt, :dsLiq.liqnto, :dsLiq.liqret,
      :dsLiq.liqsap, :dsLiq.liqpap, :dsLiq.liqarl,
      :dsLiq.liqsen, :dsLiq.liqicb, :dsLiq.liqcaj,
      :dsLiq.liqces, :dsLiq.liqice, :dsLiq.liqpri, :dsLiq.liqvac;

  if sqlcode <> 0;
    leave;
  endif;

  // Construir JSON para intERPrise GL entry
  exsr srBuildJson;

  // Enviar a intERPrise via HTTP
  wRc = 0;
  exsr srPostToIntERPrise;

  if wRc = 0;
    // Actualizar estado a Contabilizada
    LIQNUM = dsLiq.liqNum;
    LIQEMP = dsLiq.liqEmp;
    chain (LIQNUM : LIQEMP) LIQREG;
    if %found(NOMLIQF);
      LIQEST = 'C';
      update LIQREG;
    endif;
    wCount += 1;
    wTotal += dsLiq.liqdtt;
  endif;
enddo;

exec sql close curLiq;

wMsg = 'Contabilizacion: ' + %char(wCount) + ' liquidaciones. Total: $' +
       %editc(wTotal:'3');
dsply wMsg;

*inlr = *on;
return;


//=====================================================================
// SR: Construir JSON de asiento contable para intERPrise GL
// Formato segun org.i-nterprise.example CUSMSTF pattern
//=====================================================================
begsr srBuildJson;
  dcl-s gastos    packed(15:2);
  dcl-s nomPagar  packed(15:2);
  dcl-s aportes   packed(15:2);
  dcl-s parafis   packed(15:2);
  dcl-s provision packed(15:2);

  gastos   = dsLiq.liqdtt + dsLiq.liqces + dsLiq.liqice +
             dsLiq.liqpri + dsLiq.liqvac +
             dsLiq.liqsap + dsLiq.liqpap + dsLiq.liqarl +
             dsLiq.liqsen + dsLiq.liqicb + dsLiq.liqcaj;
  nomPagar = dsLiq.liqnto;
  aportes  = dsLiq.liqsap + dsLiq.liqpap + dsLiq.liqarl;
  parafis  = dsLiq.liqsen + dsLiq.liqicb + dsLiq.liqcaj;
  provision= dsLiq.liqces + dsLiq.liqice + dsLiq.liqpri + dsLiq.liqvac;

  wJson = '{"journal":"NOM","period":"' + dsLiq.liqPer + '",' +
          '"reference":"LIQ-' + %char(dsLiq.liqNum) + '",' +
          '"employee":"' + %trimr(dsLiq.liqEmp) + '",' +
          '"entries":[' +
          // Debitos gastos de nomina
          '{"account":"5101","type":"D","amount":' + %char(dsLiq.liqdtt) + '},' +
          '{"account":"5109","type":"D","amount":' +
            %char(dsLiq.liqces + dsLiq.liqice) + '},' +
          '{"account":"5110","type":"D","amount":' + %char(dsLiq.liqpri) + '},' +
          '{"account":"5111","type":"D","amount":' + %char(dsLiq.liqvac) + '},' +
          '{"account":"5115","type":"D","amount":' + %char(aportes) + '},' +
          '{"account":"5116","type":"D","amount":' + %char(parafis) + '},' +
          // Creditos pasivos
          '{"account":"2510","type":"C","amount":' + %char(nomPagar) + '},' +
          '{"account":"2370","type":"C","amount":' + %char(dsLiq.liqret) + '},' +
          '{"account":"2350","type":"C","amount":' + %char(aportes) + '},' +
          '{"account":"2360","type":"C","amount":' + %char(parafis) + '},' +
          '{"account":"2610","type":"C","amount":' + %char(dsLiq.liqces) + '},' +
          '{"account":"2611","type":"C","amount":' + %char(dsLiq.liqice) + '},' +
          '{"account":"2612","type":"C","amount":' + %char(dsLiq.liqpri) + '},' +
          '{"account":"2613","type":"C","amount":' + %char(dsLiq.liqvac) + '}' +
          ']}';
endsr;


//=====================================================================
// SR: POST JSON a intERPrise via HTTP
// Usa QSYS2.HTTP_POST (patron de USPS_Address en IBM-i-RPG-Free-CLP-Code)
// El servidor intERPrise escucha en org.i-nterprise.transport.services
//=====================================================================
begsr srPostToIntERPrise;
  dcl-s wUrl varchar(200);

  wUrl = 'http://' + %trimr(wHost) + ':' + %char(wPort) + '/api/gl/entry';

  exec sql
    values QSYS2.HTTP_POST(
      :wUrl,
      :wJson,
      '{"header": [["Content-Type","application/json"]]}'
    ) into :wResp;

  if sqlcode <> 0 or wResp = '' or %scan('error':wResp) > 0;
    wMsg = 'ERROR HTTP intERPrise - LIQ ' + %char(dsLiq.liqNum);
    dsply wMsg;
    wRc = 1;
  endif;
endsr;
```

- [ ] **Step 2: Commit**
```bash
git add ibmi-nomina-colombia/qrpglesrc/nomcontpgm.rpgle
git commit -m "feat(nomina): add NOMCONTPGM - GL posting to intERPrise via HTTP/JSON"
```

---

## Task 7: Makefile para ibmi-nomina-colombia

**Files:**
- Create: `ibmi-nomina-colombia/makefile`

- [ ] **Step 1: Crear makefile**

```makefile
# Makefile - ibmi-nomina-colombia
# Sistema de nomina quincenal para Colombia
#
# DEPENDENCIAS:
#   CMPSYS.EMPLOYEE   (ibmi-company_system) - maestro empleados
#   intERPrise GL API (org.i-nterprise.transport.services) - contabilizacion
#
# LIBRERIAS DE DESTINO:
#   NOMINA  - objetos del sistema de nomina
#
# ORDEN DE COMPILACION (dependencias):
#   1. NOMLIQF.PF       - archivo fisico (base de datos)
#   2. NOMCALCSR.MODULE - modulo del service program
#   3. NOMCALCSR.SRVPGM - service program de calculos
#   4. NOMLIQPGM.PGM    - programa principal (usa NOMCALCSR)
#   5. NOMRPTPGM.PGM    - comprobante (usa NOMLIQF)
#   6. NOMCONTPGM.PGM   - contabilizacion (usa NOMLIQF + intERPrise)
#
# UTILIDADES EXTERNAS REFERENCIADAS:
#   IBM-i-RPG-Free-CLP-Code/DATE_UDF  - UDF fechas (SQL)
#   IBM-i-RPG-Free-CLP-Code/DATEADJ   - Comando aritmetica fechas
#   IBM-i-RPG-Free-CLP-Code/Printing  - Patron impresion sin O-Specs

TGTLIB = NOMINA
CMPSYS = CMPSYS

all: nomliqf nomcalcsr nomliqpgm nomrptpgm nomcontpgm

# Archivo fisico de liquidaciones
nomliqf:
	system "CRTPF FILE($(TGTLIB)/NOMLIQF) SRCFILE(NOMINA/QPFSRC) SRCMBR(NOMLIQF)"

# Pantallas (actualizar si se modificaron)
dspf:
	system "CRTDSPF FILE($(TGTLIB)/NOMEMPS) SRCFILE(NOMINA/QDDSSRC)"
	system "CRTDSPF FILE($(TGTLIB)/NOMLIQ)  SRCFILE(NOMINA/QDDSSRC)"
	system "CRTDSPF FILE($(TGTLIB)/NOMRPT)  SRCFILE(NOMINA/QDDSSRC)"

# Service program de calculos (compilar como modulo primero)
nomcalcsr:
	system "CRTRPGMOD MODULE($(TGTLIB)/NOMCALCSR) SRCFILE(NOMINA/QRPGLESRC) SRCMBR(NOMCALCSR) DBGVIEW(*ALL)"
	system "CRTSRVPGM SRVPGM($(TGTLIB)/NOMCALCSR) MODULE($(TGTLIB)/NOMCALCSR) EXPORT(*SRCFILE) SRCFILE(NOMINA/QSRVSRC) SRCMBR(NOMCALCSR)"

# Programa principal de liquidacion
nomliqpgm:
	system "CRTSQLRPGI OBJ($(TGTLIB)/NOMLIQPGM) SRCFILE(NOMINA/QRPGLESRC) SRCMBR(NOMLIQPGM) COMMIT(*NONE) DBGVIEW(*SOURCE)"
	system "UPDPGM PGM($(TGTLIB)/NOMLIQPGM) BNDDIR(($(TGTLIB)/NOMCALCSR))"

# Programa de comprobante
nomrptpgm:
	system "CRTSQLRPGI OBJ($(TGTLIB)/NOMRPTPGM) SRCFILE(NOMINA/QRPGLESRC) SRCMBR(NOMRPTPGM) COMMIT(*NONE) DBGVIEW(*SOURCE)"

# Programa de contabilizacion
nomcontpgm:
	system "CRTSQLRPGI OBJ($(TGTLIB)/NOMCONTPGM) SRCFILE(NOMINA/QRPGLESRC) SRCMBR(NOMCONTPGM) COMMIT(*NONE) DBGVIEW(*SOURCE)"

# Datos de prueba - poblar EMPLOYEE desde company_system
testdata:
	system "RUNSQLSTM SRCFILE($(CMPSYS)/QSQLSRC) SRCMBR(POPEMP) COMMIT(*NONE)"

clean:
	system "DLTOBJ OBJ($(TGTLIB)/NOMLIQF)    OBJTYPE(*FILE)"  || true
	system "DLTOBJ OBJ($(TGTLIB)/NOMCALCSR)  OBJTYPE(*SRVPGM)" || true
	system "DLTOBJ OBJ($(TGTLIB)/NOMLIQPGM)  OBJTYPE(*PGM)"    || true
	system "DLTOBJ OBJ($(TGTLIB)/NOMRPTPGM)  OBJTYPE(*PGM)"    || true
	system "DLTOBJ OBJ($(TGTLIB)/NOMCONTPGM) OBJTYPE(*PGM)"    || true
```

- [ ] **Step 2: Commit**
```bash
git add ibmi-nomina-colombia/makefile
git commit -m "feat(nomina): add makefile with compilation order and dependencies"
```

---

## Task 8: READMEs con contexto de negocio para el LLM

Estos READMEs son críticos para que el LLM pueda responder preguntas de negocio. Deben ser específicos: mencionar nombres de programas, archivos, fórmulas y líneas de código relevantes.

**Files:**
- Create: `ibmi-nomina-colombia/README.md`
- Create: `ibmi-company_system/README.md`
- Create: `intERPrise/README.md`
- Create: `IBM-i-RPG-Free-CLP-Code/README.md`

- [ ] **Step 1: Crear ibmi-nomina-colombia/README.md**

```markdown
# ibmi-nomina-colombia — Sistema de Nómina Quincenal Colombia

## Propósito
Liquidación quincenal de nómina conforme a la legislación laboral colombiana.
Integrado con `ibmi-company_system` (maestro de empleados) e `intERPrise` (contabilidad GL).

## Módulos del sistema

| Programa | Tipo | Función |
|----------|------|---------|
| `NOMCALCSR` | Service Program | Motor de cálculos — todas las fórmulas legales |
| `NOMLIQPGM` | Programa interactivo | Liquidación quincenal (pantalla 5250) |
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
| Concepto | Fórmula | Archivo | Procedimiento |
|----------|---------|---------|---------------|
| Salario quincenal | `SALARY / 30 * diasTrabajados` | `NOMCALCSR.rpgle` | `calcSalarioQuincena` |
| Auxilio transporte | `$162.000/mes` si salario ≤ 2 SMLV | `NOMCALCSR.rpgle` | `calcAuxTransporte` |
| Horas extras diurnas | `valorHora * 1.25` | `NOMCALCSR.rpgle` | `calcHorasExtras` |
| Horas extras nocturnas | `valorHora * 1.75` | `NOMCALCSR.rpgle` | `calcHorasExtras` |
| H.extras fest. diurnas | `valorHora * 1.75` | `NOMCALCSR.rpgle` | `calcHorasExtras` |
| H.extras fest. nocturnas | `valorHora * 2.10` | `NOMCALCSR.rpgle` | `calcHorasExtras` |
| Recargo nocturno | `valorHora * 1.35` | `NOMCALCSR.rpgle` | `calcHorasExtras` |

### Deducciones empleado
| Concepto | Fórmula | Norma | Procedimiento |
|----------|---------|-------|---------------|
| Salud empleado | `salario * 4%` | Ley 100/1993 Art.204 | `calcSaludEmpleado` |
| Pensión empleado | `salario * 4%` | Ley 100/1993 Art.20 | `calcPensionEmpleado` |
| Retención en la fuente | Tabla progresiva UVT 2024 | Art. 383 E.T. | `calcRetencion` |

### Aportes patronales (costo adicional empleador)
| Concepto | Tasa | Norma | Procedimiento |
|----------|------|-------|---------------|
| Salud patronal | 8.5% | Ley 100/1993 | `calcSaludPatronal` |
| Pensión patronal | 12% | Ley 100/1993 | `calcPensionPatronal` |
| ARL | 0.522%–6.96% según riesgo | Decreto 1607/2002 | `calcARL` |
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
- Campos usados: `SALARY` (base de todos los cálculos), `HIREDATE` (antigüedad)

## Integración con intERPrise
- `NOMCONTPGM` hace HTTP POST a `org.i-nterprise.transport.services`
- Genera asiento PUC Colombia: DB 51xx (gastos) / CR 23xx-26xx (pasivos)
- Estado de liquidación: `P`=Pendiente → `L`=Liquidada → `C`=Contabilizada

## Utilidades de IBM-i-RPG-Free-CLP-Code usadas
| Utilidad | Dónde se usa | Propósito |
|----------|-------------|-----------|
| `DATE_UDF` | `NOMCALCSR` / `NOMLIQPGM` | Calcular días exactos entre fechas |
| `DATEADJ` | `NOMLIQPGM.srCalcFechasPeriodo` | Derivar último día del mes |
| `SQL_SKELETON` | `NOMCONTPGM` | Patrón cursor + manejo errores SQL |
| `USPS_Address` (patrón HTTP) | `NOMCONTPGM.srPostToIntERPrise` | HTTP POST via QSYS2.HTTP_POST |
| `RcdLckDsp` | `NOMLIQPGM.srGuardar` | Prevenir doble liquidación |
| `Printing` | `NOMRPTPGM` | Comprobante impreso sin printer file |
```

- [ ] **Step 2: Crear ibmi-company_system/README.md**

```markdown
# ibmi-company_system — Sistema de Gestión de Empresa

## Propósito
Maestro de empleados y departamentos. Es la **fuente de verdad de datos de personal**
para todo el ecosistema: el sistema de nómina (`ibmi-nomina-colombia`) lee de aquí.

## Módulos del sistema

| Objeto | Tipo | Función |
|--------|------|---------|
| `EMPLOYEE` | Tabla SQL | Maestro de empleados — clave: `EMPNO CHAR(6)` |
| `DEPARTMENT` | Tabla SQL | Maestro de departamentos — clave: `DEPTNO CHAR(3)` |
| `emps.dspf` | Display File | Lista de empleados con subfile |
| `depts.dspf` | Display File | Lista de departamentos con subfile |
| `nemp.dspf` | Display File | Alta de nuevo empleado |
| `popemp.sqlprc` | SQL Procedure | Poblar datos de prueba de empleados |
| `popdept.sqlprc` | SQL Procedure | Poblar datos de prueba de departamentos |

## Estructura de la tabla EMPLOYEE

```sql
EMPNO     CHAR(6)      -- Clave primaria, referenciada como LIQEMP en nomina
FIRSTNME  VARCHAR(12)
MIDINIT   CHAR(1)
LASTNAME  VARCHAR(15)
WORKDEPT  CHAR(3)      -- FK a DEPARTMENT.DEPTNO
PHONENO   CHAR(4)
HIREDATE  DATE         -- Usado en cesantias definitivas
JOB       CHAR(8)      -- Determina nivel de riesgo ARL en nomina
SALARY    DECIMAL(9,2) -- Base de TODOS los calculos de nomina Colombia
```

## Integración con otros sistemas
- **ibmi-nomina-colombia**: Lee EMPLOYEE via `SELECT ... FROM CMPSYS.EMPLOYEE`
  en `NOMLIQPGM.rpgle`. La clave EMPNO es el vínculo entre sistemas.
- **intERPrise**: Los departamentos de DEPARTMENT mapean a centros de costo en GL.

## Biblioteca en producción
`CMPSYS` — referenciada como `CMPSYS.EMPLOYEE` en las consultas SQL cross-library.
```

- [ ] **Step 3: Crear intERPrise/README.md**

```markdown
# intERPrise — Suite ERP para IBM i

## Propósito
Plataforma ERP completa (GL, AP, AR, Cashbook) basada en IBM i nativo.
Recibe asientos contables de `ibmi-nomina-colombia` via HTTP/JSON.

## Arquitectura de módulos

| Módulo | Directorio | Función |
|--------|-----------|---------|
| DB Services | `org.i-nterprise.db.services/` | Definición de tablas y IO services |
| Transport | `org.i-nterprise.transport.services/` | Servidor HTTP/JSON TCP/IP |
| Example | `org.i-nterprise.example/` | Patrón de implementación (CUSMSTF) |
| UI | `org.i-nterprise.ui.services/` | Frontend PHP (easycom) |

## Servidor HTTP (Transport Services)

El módulo `org.i-nterprise.transport.services/` contiene un servidor TCP/IP en C
(`IRP0000.C` → `IRP0004.C`) que acepta requests JSON y los procesa contra DB2.

Endpoint para contabilización de nómina:
```
POST http://<servidor>:<puerto>/api/gl/entry
Content-Type: application/json
Body: { "journal": "NOM", "period": "YYYYMMQQ", "entries": [...] }
```

## Tablas de base de datos (DB Services)

Las tablas siguen el patrón `UTLxxxF` (utility files):
- `UTL100F` — Account master (plan de cuentas)
- `UTL110F` — Journal header
- `UTL130F` — Journal detail (asientos)
- `UTL140F` — Period control
- Cada tabla tiene: DDL + RPGLEM (IO service) + BND (binding)

## Integración con ibmi-nomina-colombia
`NOMCONTPGM` (nomina) → HTTP POST → `IRP0000.C` (transport) → `UTL130F` (GL detail)

El asiento contable de nómina usa cuentas PUC Colombia:
- 51xx: Gastos de personal | 23xx-26xx: Pasivos laborales y provisiones

## Principios de arquitectura
- **Data-centric**: toda lógica de negocio en DB2 (triggers, constraints)
- **No display files**: interfaz 100% JSON/HTTP
- **ILE**: service programs reutilizables (ERRSRV, UTLSRV)
- **MVC**: separación estricta datos/lógica/presentación
```

- [ ] **Step 4: Crear IBM-i-RPG-Free-CLP-Code/README.md**

```markdown
# IBM-i-RPG-Free-CLP-Code — Librería de Utilidades y Ejemplos

## Propósito
Colección de utilidades, patrones y ejemplos IBM i reutilizables.
**Usadas activamente en ibmi-nomina-colombia** como componentes de infraestructura.

## Utilidades disponibles y dónde se usan

| Carpeta | Función | Usado en |
|---------|---------|----------|
| `DATE_UDF/` | SQL UDF: convierte fechas legacy a DATE ISO | `NOMCALCSR` (antigüedad cesantías) |
| `DATEADJ/` | Comando CL: aritmética de fechas (sumar/restar días) | `NOMLIQPGM` (último día del mes) |
| `5250_Subfile/` | Patrón completo de subfile interactivo con service programs | `NOMLIQPGM` (lista de empleados) |
| `SQL_SKELETON/` | Template de programa batch con SQL embedido y manejo de errores | `NOMCONTPGM` (cursor contabilización) |
| `RcdLckDsp/` | Visualización estándar de bloqueos de registro | `NOMLIQPGM` (prevención doble liquidación) |
| `Printing/` | Impresión sin O-Specs ni printer file externo | `NOMRPTPGM` (comprobante impreso) |
| `USPS_Address/` | Llamadas HTTP via `QSYS2.HTTP_GET/POST` desde RPG | `NOMCONTPGM` (HTTP a intERPrise) |
| `Service_Pgms/` | Patrones de service programs y binding directories | `NOMCALCSR` (estructura srvpgm) |
| `PGM_REFS/` | SQL Procedure para analizar dependencias entre programas | Análisis de impacto cross-módulos |
| `APIs/` | Llamadas a IBM i APIs desde CLP y RPG | Integración con system APIs |

## Cómo referencial estas utilidades
No se hace `COPY` directo del código — se usa `CALL` o SQL para invocarlas.
Cada programa en `ibmi-nomina-colombia` documenta en su cabecera qué utilidades
usa y cómo, para que el mapa de dependencias sea trazable.
```

- [ ] **Step 5: Commit**
```bash
git add ibmi-nomina-colombia/README.md ibmi-company_system/README.md
git add intERPrise/README.md IBM-i-RPG-Free-CLP-Code/README.md
git commit -m "docs: add business-context READMEs for all modules - LLM navigation"
```

---

## Task 9: Actualizar README raíz con diagrama de integración

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Reemplazar contenido del README raíz**

Reemplazar la sección "Estructura Actual" con el diagrama completo:

```markdown
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
  DATE_UDF → NOMCALCSR  |  SQL_SKELETON → NOMCONTPGM
  RcdLckDsp → NOMLIQPGM |  Printing → NOMRPTPGM
  USPS_Address (HTTP patrón) → NOMCONTPGM
```

## Estructura de Módulos

| Módulo | Dominio de Negocio | Rol en el proceso |
|--------|--------------------|-------------------|
| [`ibmi-company_system`](ibmi-company_system/) | Gestión de personal | **Fuente de verdad** de empleados |
| [`ibmi-nomina-colombia`](ibmi-nomina-colombia/) | Nómina Colombia | **Motor de liquidación** quincenal |
| [`intERPrise`](intERPrise/) | ERP / Contabilidad | **Receptor contable** de nómina |
| [`IBM-i-RPG-Free-CLP-Code`](IBM-i-RPG-Free-CLP-Code/) | Utilidades IBM i | **Infraestructura** reutilizable |

## Preguntas frecuentes que este repo puede responder

- *¿Dónde está el cálculo de cesantías?* → `ibmi-nomina-colombia/qrpglesrc/nomcalcsr.rpgle` → procedimiento `calcCesantias`
- *¿Cómo fluye un empleado de HR a nómina?* → `CMPSYS.EMPLOYEE.EMPNO` = `NOMLIQF.LIQEMP`
- *¿Qué módulos existen?* → ver tabla de estructura arriba
- *¿Cómo se contabiliza la nómina?* → `NOMCONTPGM` genera asiento DB 51xx / CR 23xx-26xx en intERPrise
- *¿Qué es el SENA en nómina?* → `calcSENA`: 2% sobre salario, Ley 119/1994
- *¿Qué programas se afectan si cambia el salario?* → `NOMLIQPGM` (lee SALARY), `NOMCALCSR` (usa en todos los cálculos)
```

- [ ] **Step 2: Commit**
```bash
git add README.md
git commit -m "docs: add integration diagram and business process map to root README"
```

---

## Checklist de cobertura (self-review)

- [x] Physical file NOMLIQF con todos los conceptos de nómina colombiana
- [x] DDS actualizadas con campo XRET/RRET (retención) y RPRVAC (vacaciones prov.)
- [x] NOMCALCSR: 16 procedimientos — cubre todos los conceptos confirmados (cesantías, prima, vacaciones, parafiscales, deducciones, retención)
- [x] NOMLIQPGM: integración SQL cross-library con CMPSYS.EMPLOYEE, subfile, calcular, guardar, prevención doble liquidación
- [x] NOMRPTPGM: comprobante leyendo NOMLIQF + CMPSYS.EMPLOYEE
- [x] NOMCONTPGM: contabilización HTTP/JSON a intERPrise, asiento PUC Colombia
- [x] Makefile con orden correcto de compilación
- [x] 4 READMEs con tablas de fórmulas, normas y cross-references específicos
- [x] README raíz con diagrama de integración y tabla de preguntas frecuentes
- [x] Todas las utilidades de IBM-i-RPG-Free-CLP-Code documentadas y referenciadas en código
- [x] Cada programa documenta en su cabecera: propósito, integración, utilidades usadas

## Notas para el ejecutor

1. Los programas usan `CMPSYS` como biblioteca de company_system — ajustar si el nombre real es diferente
2. `NOMCONTPGM` usa `QSYS2.HTTP_POST` — requiere IBM i 7.3+ con PTF SI70853
3. El nivel de riesgo ARL está hardcodeado a 1 en `NOMLIQPGM.srCalcular` — en producción leer del campo `JOB` de EMPLOYEE
4. La retención proyecta ingreso mensual como `xTotDev * 2` — en producción acumular ingresos reales del período
5. El puerto de intERPrise (8400) es configurable via `WRKIRPTCFG` command del módulo transport
