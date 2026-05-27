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
//   Puerto: 8400 por defecto (configurable via WRKIRPTCFG command)
//   Endpoint: HTTP POST /api/gl/entry
//
// PATRON DE BATCH:
//   Basado en SQL_SKELETON (IBM-i-RPG-Free-CLP-Code/SQL_SKELETON)
//   para manejo estandar de cursores, error handling y commit/rollback
//
// HTTP desde RPG:
//   Usa QSYS2.HTTP_POST (patron de USPS_Address en
//   IBM-i-RPG-Free-CLP-Code/USPS_Address) para llamadas HTTP
//   sin necesidad de socket programming en C
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
//   Patron ERRSRV de org.i-nterprise.db.services para logging
//   estandar de errores de integracion
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

ctl-opt dftactgrp(*no) actgrp('NOMCONTAB') option(*srcstmt);

// Archivo de liquidaciones
dcl-f NOMLIQF disk(*ext) usage(*update) keyed;

// Variables HTTP
dcl-s wHost    char(50)    inz('localhost');
dcl-s wPort    packed(5:0) inz(8400);
dcl-s wJson    varchar(5000);
dcl-s wResp    varchar(1000);
dcl-s wRc      packed(3:0);

// Variables de proceso
dcl-s wPeriodo char(8);
dcl-s wCount   packed(7:0);
dcl-s wTotal   packed(15:2);
dcl-s wMsg     char(78);

// DS para datos de liquidacion
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

// Parametro de entrada
dcl-pi NOMCONTPGM;
  pPeriodo char(8);
end-pi;

wPeriodo = pPeriodo;

//=====================================================================
// MAINLINE - Patron SQL_SKELETON (IBM-i-RPG-Free-CLP-Code/SQL_SKELETON)
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

  exsr srBuildJson;
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
// Formato: { journal, period, reference, employee, entries: [...] }
// Cada entry: { account (PUC), type (D/C), amount }
//=====================================================================
begsr srBuildJson;
  dcl-s gastos    packed(15:2);
  dcl-s aportes   packed(15:2);
  dcl-s parafis   packed(15:2);

  gastos   = dsLiq.liqdtt + dsLiq.liqces + dsLiq.liqice +
             dsLiq.liqpri + dsLiq.liqvac +
             dsLiq.liqsap + dsLiq.liqpap + dsLiq.liqarl +
             dsLiq.liqsen + dsLiq.liqicb + dsLiq.liqcaj;
  aportes  = dsLiq.liqsap + dsLiq.liqpap + dsLiq.liqarl;
  parafis  = dsLiq.liqsen + dsLiq.liqicb + dsLiq.liqcaj;

  wJson = '{"journal":"NOM","period":"' + dsLiq.liqPer + '",' +
          '"reference":"LIQ-' + %char(dsLiq.liqNum) + '",' +
          '"employee":"' + %trimr(dsLiq.liqEmp) + '",' +
          '"entries":[' +
          '{"account":"5101","type":"D","amount":' + %char(dsLiq.liqdtt) + '},' +
          '{"account":"5109","type":"D","amount":' +
            %char(dsLiq.liqces + dsLiq.liqice) + '},' +
          '{"account":"5110","type":"D","amount":' + %char(dsLiq.liqpri) + '},' +
          '{"account":"5111","type":"D","amount":' + %char(dsLiq.liqvac) + '},' +
          '{"account":"5115","type":"D","amount":' + %char(aportes) + '},' +
          '{"account":"5116","type":"D","amount":' + %char(parafis) + '},' +
          '{"account":"2510","type":"C","amount":' + %char(dsLiq.liqnto) + '},' +
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

  wRc  = 0;
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
