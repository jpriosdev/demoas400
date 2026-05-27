**free
/title NOMCONTPGM - Contabilizacion de Nomina → erp-financiero
//==============================================================
// Programa: NOMCONTPGM
// Libreria: NOMINA
// Funcion : Lee liquidaciones del periodo (nomina_liq con estado
//           'CA'=Calculado), construye asientos PUC Colombia y
//           los envia a erp-financiero via QSYS2.HTTP_POST.
//           Actualiza estado a 'CO' (Contabilizado) al exito.
// Parametro: periodo_id  CHAR(8)  ej. '20240101'
// Compilar : CRTSQLRPGI OBJ(NOMINA/NOMCONTPGM)
//            SRCFILE(NOMINA/QRPGLESRC) COMMIT(*NONE)
// Integracion: HTTP POST → http://localhost:8400/api/gl/entry
//              (servidor de transporte C de erp-financiero)
//==============================================================
// Cuentas PUC Colombia usadas:
//   Debitos  (Gastos): 5101 Salarios, 5109 Cesantias+Int,
//                      5110 Prima, 5111 Vacaciones,
//                      5115 SS empleador, 5116 Parafiscales
//   Creditos (Pasivos):2510 Nomina por pagar (neto),
//                      2370 Retencion en la fuente,
//                      2350 SS a cargo empleado,
//                      2610 Cesantias, 2612 Prima, 2613 Vacaciones
//==============================================================
ctl-opt dftactgrp(*no) actgrp('NOMINA') option(*nodebugio:*srcstmt);

/copy 'qrpgleref/nomina.rpgleinc'

dcl-pi NOMCONTPGM;
  pPeriodo  char(8);
end-pi;

// === Variables de trabajo =====================================================
dcl-s wUrl     varchar(200) inz('http://localhost:8400/api/gl/entry');
dcl-s wHeaders varchar(200)
      inz('{"header":[["Content-Type","application/json"]]}');
dcl-s wJson    clob(32000)  inz('');
dcl-s wResp    clob(32000)  inz('');
dcl-s wCnt     int(10)      inz(0);

// Totales acumulados del periodo — un asiento por cuenta PUC
dcl-s wTotSal    packed(15:2) inz(0);  // 5101 Salarios
dcl-s wTotCes    packed(15:2) inz(0);  // 5109 Cesantias + int.ces.
dcl-s wTotPri    packed(15:2) inz(0);  // 5110 Prima de servicios
dcl-s wTotVac    packed(15:2) inz(0);  // 5111 Vacaciones
dcl-s wTotSSEmp  packed(15:2) inz(0);  // 5115 Aportes SS empleador
dcl-s wTotPar    packed(15:2) inz(0);  // 5116 Parafiscales
dcl-s wTotNeto   packed(15:2) inz(0);  // 2510 Nomina por pagar
dcl-s wTotRet    packed(15:2) inz(0);  // 2370 Retencion en la fuente
dcl-s wTotSSDed  packed(15:2) inz(0);  // 2350 SS empleado (deduccion)

// === 1. Acumular totales del periodo (solo estado='CA') =======================
exec sql
  select count(*),
         coalesce(sum(total_devengado),              0),
         coalesce(sum(prov_cesantias + prov_int_ces),0),
         coalesce(sum(prov_prima),                   0),
         coalesce(sum(prov_vacaciones),              0),
         coalesce(sum(salud_emp_comp + pension_emp_comp + arl), 0),
         coalesce(sum(sena + icbf + caja_comp),      0),
         coalesce(sum(neto_pagar),                   0),
         coalesce(sum(retencion_fte),                0),
         coalesce(sum(salud_emp + pension_emp),      0)
    into :wCnt,
         :wTotSal,  :wTotCes, :wTotPri,  :wTotVac,
         :wTotSSEmp,:wTotPar,
         :wTotNeto, :wTotRet, :wTotSSDed
    from nomina_liq
   where periodo_id = :pPeriodo
     and estado     = 'CA';

if wCnt = 0;
  *inlr = *on;
  return;
endif;

// === 2. Construir JSON con asientos PUC ======================================
wJson = '{"periodo":"' concat %trim(pPeriodo)    concat '",'
      concat '"tipo":"NOMINA",'
      concat '"empleados":' concat %char(wCnt)   concat ','
      concat '"registros":['
        // Debitos (Gastos)
        concat '{"cuenta":"5101","tipo":"D","desc":"Salarios",'
        concat  '"valor":' concat %char(wTotSal)   concat '},'
        concat '{"cuenta":"5109","tipo":"D","desc":"Cesantias e int.",'
        concat  '"valor":' concat %char(wTotCes)   concat '},'
        concat '{"cuenta":"5110","tipo":"D","desc":"Prima servicios",'
        concat  '"valor":' concat %char(wTotPri)   concat '},'
        concat '{"cuenta":"5111","tipo":"D","desc":"Vacaciones",'
        concat  '"valor":' concat %char(wTotVac)   concat '},'
        concat '{"cuenta":"5115","tipo":"D","desc":"SS empleador",'
        concat  '"valor":' concat %char(wTotSSEmp) concat '},'
        concat '{"cuenta":"5116","tipo":"D","desc":"Parafiscales",'
        concat  '"valor":' concat %char(wTotPar)   concat '},'
        // Creditos (Pasivos)
        concat '{"cuenta":"2510","tipo":"C","desc":"Nomina por pagar",'
        concat  '"valor":' concat %char(wTotNeto)  concat '},'
        concat '{"cuenta":"2370","tipo":"C","desc":"Retencion fte.",'
        concat  '"valor":' concat %char(wTotRet)   concat '},'
        concat '{"cuenta":"2350","tipo":"C","desc":"SS empleado",'
        concat  '"valor":' concat %char(wTotSSDed) concat '},'
        concat '{"cuenta":"2610","tipo":"C","desc":"Cesantias",'
        concat  '"valor":' concat %char(wTotCes)   concat '},'
        concat '{"cuenta":"2612","tipo":"C","desc":"Prima",'
        concat  '"valor":' concat %char(wTotPri)   concat '},'
        concat '{"cuenta":"2613","tipo":"C","desc":"Vacaciones",'
        concat  '"valor":' concat %char(wTotVac)   concat '}'
      concat ']}';

// === 3. POST a erp-financiero =================================================
exec sql
  values QSYS2.HTTP_POST(:wUrl, :wJson, :wHeaders)
    into :wResp;

// === 4. Marcar registros como contabilizados (CO) ============================
if sqlcode = 0;
  exec sql
    update nomina_liq
       set estado       = 'CO',
           ts_liquidado = current_timestamp
     where periodo_id   = :pPeriodo
       and estado       = 'CA';
endif;

*inlr = *on;
return;
