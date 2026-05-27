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
  ind05 ind pos(05);
  ind06 ind pos(06);
  ind10 ind pos(10);
  ind12 ind pos(12);
  ind85 ind pos(85);
  ind95 ind pos(95);
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

// Variables de pantalla NOMLIQ
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
  ind85 = *off;
  ind95 = *off;
  wSflRrn = 0;

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
      when ind05;
        exsr srCalcular;
      when ind10;
        exsr srGuardar;
        leave;
    endsl;
  enddo;
endsr;


//=====================================================================
// SR: Calcular todos los conceptos de nomina colombiana
// Delega en NOMCALCSR service program
//=====================================================================
begsr srCalcular;
  wDiasAcm = (%subdt(%date():*months) - 1) * 30 + xDias;

  xSalQna  = calcSalarioQuincena(wSalMes : xDias);
  xAuxTrp  = calcAuxTransporte(wSalMes : xDias);
  xVHext   = calcHorasExtras(wSalMes : xHed : xHen : xHefd : xHefn : xRno);
  xTotDev  = xSalQna + xAuxTrp + xVHext;

  xSalEmp  = calcSaludEmpleado(wSalMes);
  xPenEmp  = calcPensionEmpleado(wSalMes);
  xRet     = calcRetencion(xTotDev * 2);
  xTotDed  = xSalEmp + xPenEmp + xOded + xRet;
  xNeto    = xTotDev - xTotDed;

  xSalCmp  = calcSaludPatronal(wSalMes);
  xPenCmp  = calcPensionPatronal(wSalMes);
  xArl     = calcARL(wSalMes : 1);
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

  exec sql
    select coalesce(max(LIQNUM), 0) + 1
    into   :wLiqNum
    from   NOMINA.NOMLIQF;

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
// Compatible con DATE_UDF (IBM-i-RPG-Free-CLP-Code/DATE_UDF)
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
