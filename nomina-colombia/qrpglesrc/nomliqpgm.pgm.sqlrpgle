**free
Ctl-Opt DFTACTGRP(*no) BNDDIR('NOM');

Dcl-Pi NOMLIQPGM;
  InEmpNo   Char(6);
  InPeriodo Char(8);
End-Pi;

/copy 'qrpgleref/nomina.rpgleinc'

Dcl-C F05   X'35';
Dcl-C F10   X'3A';
Dcl-C F12   X'3C';

Dcl-F nomliq WORKSTN IndDS(WkStnInd) InfDS(FileInfo);

Dcl-DS WkStnInd;
End-DS;

Dcl-DS FileInfo;
  FunKey  Char(1)  Pos(369);
End-DS;

Dcl-S Exit  Ind           Inz(*Off);
Dcl-Ds liq  LikeDS(nomina_liq_t) Inz;

InicializarPantalla();

Dow Not Exit;
  Write LIQFOOTER;
  Exfmt LIQFMT;
  Select;
    When FunKey = F12;
      Exit = *On;
    When FunKey = F05;
      LeerEntradas();
      Calcular();
      MostrarResultado();
    When FunKey = F10;
      LeerEntradas();
      Calcular();
      MostrarResultado();
      guardarLiquidacion(liq);
      Exit = *On;
  Endsl;
Enddo;

*INLR = *On;
Return;

// ─────────────────────────────────────────────────────────────────────────────
Dcl-Proc InicializarPantalla;
  Dcl-S lFecIni Char(10);
  Dcl-S lFecFin Char(10);

  XEMPNO = InEmpNo;
  XPER   = InPeriodo;
  XDIAS  = 15;

  Exec Sql
    Select trim(firstnme) concat ' ' concat trim(lastname)
      Into :XNOMBRE
      From employee
     Where empno = :InEmpNo;

  Exec Sql
    Select char(fecha_ini, ISO), char(fecha_fin, ISO)
      Into :lFecIni, :lFecFin
      From nomina_periodo
     Where periodo_id = :InPeriodo;
  If SqlCode = 0;
    XFECINI = lFecIni;
    XFECFIN = lFecFin;
  Endif;

  // Cargar entradas previas si ya fue liquidado
  Exec Sql
    Select dias_trab, horas_ext_diur, horas_ext_noc,
           horas_ext_fest_d, horas_ext_fest_n, horas_rec_noc, otras_ded
      Into :XDIAS, :XHED, :XHEN, :XHEFD, :XHEFN, :XRNO, :XODED
      From nomina_liq
     Where empno = :InEmpNo And periodo_id = :InPeriodo;
End-Proc;

Dcl-Proc LeerEntradas;
  liq.empno          = InEmpNo;
  liq.periodo_id     = InPeriodo;
  liq.dias_trab      = XDIAS;
  liq.horas_ext_diur   = XHED;
  liq.horas_ext_noc    = XHEN;
  liq.horas_ext_fest_d = XHEFD;
  liq.horas_ext_fest_n = XHEFN;
  liq.horas_rec_noc    = XRNO;
  liq.otras_ded        = XODED;
End-Proc;

Dcl-Proc Calcular;
  liq = calcularLiquidacion(
          InEmpNo : InPeriodo :
          liq.dias_trab :
          liq.horas_ext_diur  : liq.horas_ext_noc :
          liq.horas_ext_fest_d : liq.horas_ext_fest_n :
          liq.horas_rec_noc   : liq.otras_ded);
End-Proc;

Dcl-Proc MostrarResultado;
  XSALQNA  = liq.salario_quincena;
  XAUXTRP  = liq.aux_transporte;
  XVHEXT   = liq.valor_hext;
  XTOTDEV  = liq.total_devengado;
  XSALEMP  = liq.salud_emp;
  XPENEMP  = liq.pension_emp;
  XTOTDED  = liq.total_deduccion;
  XNETO    = liq.neto_pagar;
  XSALCOMP = liq.salud_emp_comp;
  XPENCOMP = liq.pension_emp_comp;
  XARL     = liq.arl;
  XSENA    = liq.sena;
  XICBF    = liq.icbf;
  XCAJA    = liq.caja_comp;
  XPRCES   = liq.prov_cesantias;
  XPRINT   = liq.prov_int_ces;
  XPRPRI   = liq.prov_prima;
  XPRVAC   = liq.prov_vacaciones;
  XCOSTOT  = liq.costo_total;
End-Proc;
