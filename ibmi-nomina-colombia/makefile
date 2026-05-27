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

nomliqf:
	system "CRTPF FILE($(TGTLIB)/NOMLIQF) SRCFILE(NOMINA/QPFSRC) SRCMBR(NOMLIQF)"

dspf:
	system "CRTDSPF FILE($(TGTLIB)/NOMEMPS) SRCFILE(NOMINA/QDDSSRC)"
	system "CRTDSPF FILE($(TGTLIB)/NOMLIQ)  SRCFILE(NOMINA/QDDSSRC)"
	system "CRTDSPF FILE($(TGTLIB)/NOMRPT)  SRCFILE(NOMINA/QDDSSRC)"

nomcalcsr:
	system "CRTRPGMOD MODULE($(TGTLIB)/NOMCALCSR) SRCFILE(NOMINA/QRPGLESRC) SRCMBR(NOMCALCSR) DBGVIEW(*ALL)"
	system "CRTSRVPGM SRVPGM($(TGTLIB)/NOMCALCSR) MODULE($(TGTLIB)/NOMCALCSR) EXPORT(*SRCFILE) SRCFILE(NOMINA/QSRVSRC) SRCMBR(NOMCALCSR)"

nomliqpgm:
	system "CRTSQLRPGI OBJ($(TGTLIB)/NOMLIQPGM) SRCFILE(NOMINA/QRPGLESRC) SRCMBR(NOMLIQPGM) COMMIT(*NONE) DBGVIEW(*SOURCE)"
	system "UPDPGM PGM($(TGTLIB)/NOMLIQPGM) BNDDIR(($(TGTLIB)/NOMCALCSR))"

nomrptpgm:
	system "CRTSQLRPGI OBJ($(TGTLIB)/NOMRPTPGM) SRCFILE(NOMINA/QRPGLESRC) SRCMBR(NOMRPTPGM) COMMIT(*NONE) DBGVIEW(*SOURCE)"

nomcontpgm:
	system "CRTSQLRPGI OBJ($(TGTLIB)/NOMCONTPGM) SRCFILE(NOMINA/QRPGLESRC) SRCMBR(NOMCONTPGM) COMMIT(*NONE) DBGVIEW(*SOURCE)"

testdata:
	system "RUNSQLSTM SRCFILE($(CMPSYS)/QSQLSRC) SRCMBR(POPEMP) COMMIT(*NONE)"

clean:
	system "DLTOBJ OBJ($(TGTLIB)/NOMLIQF)    OBJTYPE(*FILE)"  || true
	system "DLTOBJ OBJ($(TGTLIB)/NOMCALCSR)  OBJTYPE(*SRVPGM)" || true
	system "DLTOBJ OBJ($(TGTLIB)/NOMLIQPGM)  OBJTYPE(*PGM)"    || true
	system "DLTOBJ OBJ($(TGTLIB)/NOMRPTPGM)  OBJTYPE(*PGM)"    || true
	system "DLTOBJ OBJ($(TGTLIB)/NOMCONTPGM) OBJTYPE(*PGM)"    || true
