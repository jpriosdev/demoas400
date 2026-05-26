**free
Ctl-Opt DFTACTGRP(*no) BNDDIR('NOM');

Dcl-Pi NOMRPTPGM;
  InEmpNo   Char(6);
  InPeriodo Char(8);
End-Pi;

Dcl-F nomrpt WORKSTN IndDS(WkStnInd) InfDS(FileInfo);

Dcl-DS WkStnInd;
End-DS;

Dcl-DS FileInfo;
  FunKey  Char(1)  Pos(369);
End-DS;

CargarComprobante();
Write RPTFOOTER;
Exfmt RPTFMT;

*INLR = *On;
Return;

// ─────────────────────────────────────────────────────────────────────────────
Dcl-Proc CargarComprobante;
  Dcl-S lFecIni Char(10);
  Dcl-S lFecFin Char(10);

  REMPNO = InEmpNo;
  RPER   = InPeriodo;

  Exec Sql
    Select trim(firstnme) concat ' ' concat trim(lastname)
      Into :RNOMBRE
      From employee
     Where empno = :InEmpNo;

  Exec Sql
    Select char(np.fecha_ini, ISO),
           char(np.fecha_fin, ISO),
           nl.dias_trab,
           nl.salario_quincena, nl.aux_transporte,
           nl.valor_hext,       nl.total_devengado,
           nl.salud_emp,        nl.pension_emp,
           nl.otras_ded,        nl.total_deduccion,
           nl.neto_pagar,
           nl.salud_emp_comp,   nl.pension_emp_comp,
           nl.arl,              nl.sena,
           nl.icbf,             nl.caja_comp,
           nl.prov_cesantias,   nl.prov_int_ces,
           nl.prov_prima,       nl.prov_vacaciones
      Into :lFecIni,  :lFecFin,
           :RDIAS,
           :RSALQNA,  :RAUXTRP,
           :RVHEXT,   :RTOTDEV,
           :RSALEMP,  :RPENEMP,
           :RODED,    :RTOTDED,
           :RNETO,
           :RSALCOMP, :RPENCOMP,
           :RARL,     :RSENA,
           :RICBF,    :RCAJA,
           :RPRCES,   :RPRINT,
           :RPRPRI,   :RPRVAC
      From nomina_liq nl
      Join nomina_periodo np On np.periodo_id = nl.periodo_id
     Where nl.empno      = :InEmpNo
       And nl.periodo_id = :InPeriodo;

  If SqlCode = 0;
    RFECINI = lFecIni;
    RFECFIN = lFecFin;
  Endif;
End-Proc;
