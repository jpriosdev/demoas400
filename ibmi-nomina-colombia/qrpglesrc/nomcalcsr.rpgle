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
dcl-c AUX_TRP_MES   162000;
dcl-c LIM_AUX_TRP  2600000;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcSalarioQuincena
// Calcula salario proporcional a los dias trabajados en el periodo
// Formula: SalarioMes / 30 * DiasLaborados
// Ejemplo: $3.000.000 / 30 * 15 = $1.500.000
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dcl-proc calcSalarioQuincena export;
  dcl-pi *n packed(13:2);
    pSalMes  packed(13:2) const;
    pDias    packed(2:0)  const;
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
    pHED     packed(5:2)  const;
    pHEN     packed(5:2)  const;
    pHEFD    packed(5:2)  const;
    pHEFN    packed(5:2)  const;
    pRNO     packed(5:2)  const;
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
    pIngresoMes packed(13:2) const;
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
    other;                tasa = 0.00522;
  endsl;

  return %dec(pSalMes * tasa : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcSENA
// Aporte al Servicio Nacional de Aprendizaje (Ley 119/1994)
// Tarifa: 2% sobre nomina mensual total de la empresa
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
    pDiasAcm packed(3:0)  const;
  end-pi;
  return %dec(pSalMes * pDiasAcm / 360 : 11 : 2);
end-proc;


//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// calcIntCesantias
// Intereses sobre cesantias (Art. 99 Ley 50/1990)
// Tarifa: 12% anual sobre saldo de cesantias
// Formula: Cesantias * 12% * DiasAcumulados / 360
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
