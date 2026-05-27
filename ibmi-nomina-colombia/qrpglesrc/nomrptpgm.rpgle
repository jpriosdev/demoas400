**FREE
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// NOMRPTPGM - Comprobante de Nomina Colombia
// Sistema: ibmi-nomina-colombia
//
// PROPOSITO:
//   Muestra el comprobante individual de liquidacion quincenal
//   en pantalla 5250 (NOMRPT.DSPF)
//
// LLAMADO DESDE: NOMLIQPGM (opcion 5 en subfile de empleados)
//
// PARAMETROS DE ENTRADA:
//   pEmpNo   (6A): Codigo del empleado (= EMPLOYEE.EMPNO en company_system)
//   pPeriodo (8A): Periodo YYYYMMQQ
//
// IMPRESION:
//   Patron de impresion sin O-Specs basado en tecnica de Printing
//   (IBM-i-RPG-Free-CLP-Code/Printing): genera comprobante en spool
//   sin necesidad de printer file externo definido
//
// DATOS:
//   Lee NOMLIQF filtrado por LIQEMP + LIQPER
//   Completa nombre desde CMPSYS.EMPLOYEE (ibmi-company_system)
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

ctl-opt dftactgrp(*no) actgrp('NOMINA') option(*srcstmt);

// Pantalla comprobante
dcl-f NOMRPT workstn indds(wsInd);

// Indicadores
dcl-ds wsInd len(99);
  ind12 ind pos(12);
end-ds;

// Parametros de entrada
dcl-pi NOMRPTPGM;
  pEmpNo   char(6);
  pPeriodo char(8);
end-pi;

// Campos de pantalla RPTFMT
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
dcl-s wFound  ind;

//=====================================================================
// MAINLINE
//=====================================================================
exec sql set option commit = *none, datfmt = *iso;

exsr srLeerLiquidacion;

if wFound;
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

  wFound = *off;

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
    return;
  endif;

  exec sql
    select trim(FIRSTNME) concat ' ' concat trim(LASTNAME)
    into :wNombre
    from CMPSYS.EMPLOYEE
    where EMPNO = :pEmpNo;

  rEmpNo  = pEmpNo;
  rNombre = wNombre;
  rPer    = pPeriodo;
  wFound  = *on;
endsr;
