BIN_LIB=DEV
APP_BNDDIR=NOM
LIBL=$(BIN_LIB)

INCDIR=""
BNDDIR=($(BIN_LIB)/$(APP_BNDDIR))
PREPATH=/QSYS.LIB/$(BIN_LIB).LIB
SHELL=/QOpenSys/usr/bin/qsh

all: .logs .evfevent library \
     $(PREPATH)/NOM.BNDDIR \
     $(PREPATH)/NOMEMPS.PGM \
     $(PREPATH)/NOMLIQPGM.PGM \
     $(PREPATH)/NOMRPTPGM.PGM

# ─── Infraestructura ──────────────────────────────────────────────────────────
.logs:
	mkdir .logs
.evfevent:
	mkdir .evfevent
library:
	-system -q "CRTLIB LIB($(BIN_LIB))"

# ─── Tablas SQL ───────────────────────────────────────────────────────────────
$(PREPATH)/NOMINA_EMP.FILE: qsqlsrc/nomina_emp.table
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "RUNSQLSTM SRCSTMF('qsqlsrc/nomina_emp.table') COMMIT(*NONE)" > .logs/nomina_emp.splf

$(PREPATH)/NOMINA_PERIODO.FILE: qsqlsrc/nomina_periodo.table
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "RUNSQLSTM SRCSTMF('qsqlsrc/nomina_periodo.table') COMMIT(*NONE)" > .logs/nomina_periodo.splf

$(PREPATH)/NOMINA_LIQ.FILE: qsqlsrc/nomina_liq.table \
                             $(PREPATH)/NOMINA_EMP.FILE \
                             $(PREPATH)/NOMINA_PERIODO.FILE
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "RUNSQLSTM SRCSTMF('qsqlsrc/nomina_liq.table') COMMIT(*NONE)" > .logs/nomina_liq.splf

# ─── Service Program NOMLIQ ───────────────────────────────────────────────────
$(PREPATH)/NOMLIQ.MODULE: qrpglesrc/nomliq.sqlrpgle \
                           $(PREPATH)/NOMINA_EMP.FILE \
                           $(PREPATH)/NOMINA_LIQ.FILE
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/NOMLIQ) SRCSTMF('qrpglesrc/nomliq.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) COMPILEOPT('TGTCCSID(*JOB)') RPGPPOPT(*LVL2) OPTION(*EVENTF) OBJTYPE(*MODULE)" > .logs/nomliq.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMLIQ.MBR') TOSTMF('.evfevent/nomliq.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMLIQ.SRVPGM: qrpglesrc/nomliq.bnd \
                           $(PREPATH)/NOMLIQ.MODULE
	-system -q "CRTBNDDIR BNDDIR($(BIN_LIB)/$(APP_BNDDIR))"
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSRVPGM SRVPGM($(BIN_LIB)/NOMLIQ) MODULE($(BIN_LIB)/NOMLIQ) SRCSTMF('qrpglesrc/nomliq.bnd') REPLACE(*YES)" > .logs/nomliq_srv.splf
	-system -q "ADDBNDDIRE BNDDIR($(BIN_LIB)/$(APP_BNDDIR)) OBJ((*LIBL/NOMLIQ *SRVPGM *IMMED))"

$(PREPATH)/NOM.BNDDIR: $(PREPATH)/NOMLIQ.SRVPGM
	-system -q "CRTBNDDIR BNDDIR($(BIN_LIB)/NOM)"
	-system -q "ADDBNDDIRE BNDDIR($(BIN_LIB)/NOM) OBJ((*LIBL/NOMLIQ *SRVPGM *IMMED))"

# ─── Tests RPGUnit ────────────────────────────────────────────────────────────
$(PREPATH)/TNOMLIQS.MODULE: qtestsrc/nomliq.test.sqlrpgle \
                             $(PREPATH)/NOMLIQ.SRVPGM
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/TNOMLIQS) SRCSTMF('qtestsrc/nomliq.test.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) COMPILEOPT('TGTCCSID(*JOB) BNDDIR(NOM)') RPGPPOPT(*LVL2) OPTION(*EVENTF) OBJTYPE(*MODULE)" > .logs/tnomliqs.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/TNOMLIQS.MBR') TOSTMF('.evfevent/tnomliqs.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

# ─── Display Files ────────────────────────────────────────────────────────────
$(PREPATH)/NOMEMPS.FILE: qddssrc/nomemps.dspf
	-system -qi "CRTSRCPF FILE($(BIN_LIB)/QTMPSRC) RCDLEN(112) CCSID(*JOB)"
	system "CPYFRMSTMF FROMSTMF('qddssrc/nomemps.dspf') TOMBR('$(PREPATH)/QTMPSRC.FILE/NOMEMPS.MBR') MBROPT(*REPLACE)"
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTDSPF FILE($(BIN_LIB)/NOMEMPS) SRCFILE($(BIN_LIB)/QTMPSRC) SRCMBR(NOMEMPS) OPTION(*EVENTF)" > .logs/nomemps_dspf.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMEMPS.MBR') TOSTMF('.evfevent/nomemps.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMLIQ.FILE: qddssrc/nomliq.dspf
	-system -qi "CRTSRCPF FILE($(BIN_LIB)/QTMPSRC) RCDLEN(112) CCSID(*JOB)"
	system "CPYFRMSTMF FROMSTMF('qddssrc/nomliq.dspf') TOMBR('$(PREPATH)/QTMPSRC.FILE/NOMLIQ.MBR') MBROPT(*REPLACE)"
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTDSPF FILE($(BIN_LIB)/NOMLIQ) SRCFILE($(BIN_LIB)/QTMPSRC) SRCMBR(NOMLIQ) OPTION(*EVENTF)" > .logs/nomliq_dspf.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMLIQ.MBR') TOSTMF('.evfevent/nomliq.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMRPT.FILE: qddssrc/nomrpt.dspf
	-system -qi "CRTSRCPF FILE($(BIN_LIB)/QTMPSRC) RCDLEN(112) CCSID(*JOB)"
	system "CPYFRMSTMF FROMSTMF('qddssrc/nomrpt.dspf') TOMBR('$(PREPATH)/QTMPSRC.FILE/NOMRPT.MBR') MBROPT(*REPLACE)"
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTDSPF FILE($(BIN_LIB)/NOMRPT) SRCFILE($(BIN_LIB)/QTMPSRC) SRCMBR(NOMRPT) OPTION(*EVENTF)" > .logs/nomrpt_dspf.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMRPT.MBR') TOSTMF('.evfevent/nomrpt.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

# ─── Programas ────────────────────────────────────────────────────────────────
$(PREPATH)/NOMEMPS.PGM: qrpglesrc/nomemps.pgm.sqlrpgle \
                         $(PREPATH)/NOMEMPS.FILE \
                         $(PREPATH)/NOM.BNDDIR \
                         $(PREPATH)/NOMINA_EMP.FILE
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/NOMEMPS) SRCSTMF('qrpglesrc/nomemps.pgm.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) OPTION(*EVENTF) RPGPPOPT(*LVL2) COMPILEOPT('TGTCCSID(*JOB) BNDDIR(NOM) DFTACTGRP(*no)')" > .logs/nomemps.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMEMPS.MBR') TOSTMF('.evfevent/nomemps.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMLIQPGM.PGM: qrpglesrc/nomliqpgm.pgm.sqlrpgle \
                            $(PREPATH)/NOMLIQ.FILE \
                            $(PREPATH)/NOM.BNDDIR
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/NOMLIQPGM) SRCSTMF('qrpglesrc/nomliqpgm.pgm.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) OPTION(*EVENTF) RPGPPOPT(*LVL2) COMPILEOPT('TGTCCSID(*JOB) BNDDIR(NOM) DFTACTGRP(*no)')" > .logs/nomliqpgm.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMLIQPGM.MBR') TOSTMF('.evfevent/nomliqpgm.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')

$(PREPATH)/NOMRPTPGM.PGM: qrpglesrc/nomrptpgm.pgm.sqlrpgle \
                            $(PREPATH)/NOMRPT.FILE \
                            $(PREPATH)/NOM.BNDDIR
	liblist -c $(BIN_LIB);\
	liblist -a $(LIBL);\
	system "CRTSQLRPGI OBJ($(BIN_LIB)/NOMRPTPGM) SRCSTMF('qrpglesrc/nomrptpgm.pgm.sqlrpgle') COMMIT(*NONE) DBGVIEW(*SOURCE) OPTION(*EVENTF) RPGPPOPT(*LVL2) COMPILEOPT('TGTCCSID(*JOB) BNDDIR(NOM) DFTACTGRP(*no)')" > .logs/nomrptpgm.splf || \
	(system "CPYTOSTMF FROMMBR('$(PREPATH)/EVFEVENT.FILE/NOMRPTPGM.MBR') TOSTMF('.evfevent/nomrptpgm.evfevent') DBFCCSID(*FILE) STMFCCSID(1208) STMFOPT(*REPLACE)"; $(SHELL) -c 'exit 1')
