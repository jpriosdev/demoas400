**free
Ctl-Opt DFTACTGRP(*no) BNDDIR('NOM');

/copy 'qrpgleref/nomina.rpgleinc'

Dcl-C F05   X'35';
Dcl-C F06   X'36';
Dcl-C F12   X'3C';
Dcl-C ENTER X'F1';

Dcl-F nomemps WORKSTN Sfile(SFLDta:Rrn) IndDS(WkStnInd) InfDS(FileInfo);

Dcl-DS WkStnInd;
  SflDspCtl  Ind  Pos(85);
  SflDsp     Ind  Pos(95);
  SflClr     Ind  Pos(75);
End-DS;

Dcl-DS FileInfo;
  FunKey  Char(1)  Pos(369);
End-DS;

Dcl-S Exit  Ind     Inz(*Off);
Dcl-S Rrn   Zoned(4:0) Inz;

// Main
LoadSubfile();
Dow Not Exit;
  Write FOOTER_FMT;
  Exfmt SFLCTL;
  Select;
    When FunKey = F12;  Exit = *On;
    When FunKey = F06;  HandleLiquidar();
    When FunKey = F05;  HandleVerRpt();
    When FunKey = ENTER; HandleInputs();
  Endsl;
Enddo;

*INLR = *On;
Return;

// ─────────────────────────────────────────────────────────────────────────────
Dcl-Proc ClearSubfile;
  SflDspCtl = *Off;
  SflDsp    = *Off;
  Write SFLCTL;
  SflDspCtl = *On;
  Rrn = 0;
End-Proc;

Dcl-Proc LoadSubfile;
  Dcl-S lEmpNo  Char(6);
  Dcl-S lNombre Varchar(50);
  Dcl-S lEstado Char(2);
  Dcl-S lNeto   Packed(13:2);
  Dcl-S lPer    Char(8);

  ClearSubfile();
  lPer = %Trim(XPERIODO);

  Exec Sql Declare empCur Cursor For
    Select e.empno,
           trim(e.firstnme) concat ' ' concat trim(e.lastname),
           coalesce(nl.estado, '--'),
           coalesce(nl.neto_pagar, 0)
      From nomina_emp ne
      Join cmpsys.employee   e  On e.empno = ne.empno
      Left Join nomina_liq nl On nl.empno = ne.empno
                             And nl.periodo_id = :lPer
     Where ne.activo = 'S'
     Order By e.lastname, e.firstnme;

  Exec Sql Open empCur;

  Dou SqlState <> '00000';
    Exec Sql Fetch Next From empCur
             Into :lEmpNo, :lNombre, :lEstado, :lNeto;

    If SqlState = '00000';
      XEMPNO  = lEmpNo;
      XNOMBRE = %Subst(lNombre : 1 : %Min(%Len(lNombre) : 25));
      XESTADO = lEstado;
      XNETO   = lNeto;
      Rrn += 1;
      Write SFLDta;
    Endif;
  Enddo;

  Exec Sql Close empCur;

  If Rrn > 0;
    SflDsp = *On;
    SFLRRN = 1;
  Endif;
End-Proc;

Dcl-Proc HandleInputs;
End-Proc;

Dcl-Proc HandleLiquidar;
  Dcl-S lPer Char(8);

  lPer = %Trim(XPERIODO);
  Dou %EOF(nomemps);
    ReadC SFLDta;
    If %EOF(nomemps); Iter; Endif;
    If %Trim(XSEL) = '6';
      Call 'NOMLIQPGM' Parm(XEMPNO : lPer);
      XSEL = *Blank;
      Update SFLDta;
    Endif;
  Enddo;
  LoadSubfile();
End-Proc;

Dcl-Proc HandleVerRpt;
  Dcl-S lPer Char(8);

  lPer = %Trim(XPERIODO);
  Dou %EOF(nomemps);
    ReadC SFLDta;
    If %EOF(nomemps); Iter; Endif;
    If %Trim(XSEL) = '5';
      Call 'NOMRPTPGM' Parm(XEMPNO : lPer);
      XSEL = *Blank;
      Update SFLDta;
    Endif;
  Enddo;
End-Proc;
