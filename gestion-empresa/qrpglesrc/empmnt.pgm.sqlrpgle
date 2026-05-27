**free
/title EMPMNT - Mantenimiento de Empleados CMPSYS
//==============================================================
// Programa: EMPMNT
// Libreria: CMPSYS   Tabla: EMPLOYEE
// Funcion : Lista, agrega, edita y elimina empleados
// Patron  : employees.pgm.sqlrpgle + MTNCUSTR.SQLRPGLE
// Compilar: CRTSQLRPGI OBJ(CMPSYS/EMPMNT) SRCFILE(CMPSYS/QRPGLESRC)
//           COMMIT(*NONE) TGTRLS(*CURRENT)
//==============================================================
ctl-opt dftactgrp(*no) actgrp('EMPMNT') option(*nodebugio:*srcstmt);

/include 'qrpgleref/constants.rpgleinc'

// === Archivo de pantalla =====================================
dcl-f empmnt workstn sfile(SFLDTA:wRRN) indds(wStnInd) infds(wInfo);

// === Indicadores de pantalla (INDARA) ========================
// N85 en DDS controla SFLCLR: cuando pos(85) = *off, el subfile se borra
dcl-ds wStnInd;
  wSflDspCtl  ind pos(85);
  wSflDsp     ind pos(95);
end-ds;

// === Informacion de archivo (tecla funcion) ==================
dcl-ds wInfo;
  wFunKey  char(1) pos(369);
end-ds;

// === Variables de trabajo =====================================
dcl-s wRRN    zoned(4:0) inz(0);
dcl-s wExit   ind        inz(*off);

// === Cuerpo principal =========================================
LoadSubfile();

dow not wExit;
  Write FOOTER;
  Exfmt SFLCTL;

  select;
    when wFunKey = F03 or wFunKey = F12;
      wExit = *on;
    when wFunKey = F06;
      AddEmployee();
      LoadSubfile();
    when wFunKey = ENTER;
      HandleInputs();
  endsl;
enddo;

*inlr = *on;
return;

//==============================================================
// ClearSubfile: borra registros del subfile antes de recargar
//==============================================================
dcl-proc ClearSubfile;
  wSflDspCtl = *off;
  wSflDsp    = *off;
  Write SFLCTL;        // escribe con indicadores apagados = borra subfile (N85 activa SFLCLR)
  wSflDspCtl = *on;
  wRRN = 0;
end-proc;

//==============================================================
// LoadSubfile: carga todos los empleados de CMPSYS.EMPLOYEE
//==============================================================
dcl-proc LoadSubfile;
  ClearSubfile();

  exec sql declare empAll cursor for
    select empno,
           trim(lastname) concat ', ' concat trim(firstnme),
           coalesce(workdept, '   '),
           coalesce(job, '        '),
           coalesce(salary, 0)
    from cmpsys.employee
    order by lastname, firstnme;

  exec sql open empAll;

  if sqlstate = '00000';
    dou sqlstate <> '00000';
      exec sql fetch next from empAll
        into :MNO, :MNOMBRE, :MDEPT, :MJOB, :MSAL;

      if sqlstate = '00000';
        MSEL  = ' ';
        wRRN += 1;
        write SFLDTA;
      endif;
    enddo;
  endif;

  exec sql close empAll;

  if wRRN > 0;
    wSflDsp = *on;
    SFLRRN  = 1;
  endif;
end-proc;

//==============================================================
// HandleInputs: procesa opciones ingresadas en el subfile
// Procesa el primer registro cambiado y recarga el subfile.
//==============================================================
dcl-proc HandleInputs;
  dcl-s lEmpNo char(6);
  dcl-s lFunc  char(1);

  lFunc = ' ';

  dou %eof(empmnt);
    readc SFLDTA;
    if %eof(empmnt);
      iter;
    endif;

    select;
      when %trim(MSEL) = '2';        // Editar
        lEmpNo = %trim(MNO);
        lFunc  = 'E';
      when %trim(MSEL) = '4';        // Eliminar
        lEmpNo = %trim(MNO);
        lFunc  = 'D';
      when %trim(MSEL) = '5';        // Visualizar
        lEmpNo = %trim(MNO);
        lFunc  = 'V';
    endsl;

    if MSEL <> ' ';
      MSEL = ' ';
      update SFLDTA;
      leave;                          // un registro por Enter
    endif;
  enddo;

  select;
    when lFunc = 'E';
      ShowDetail('E': lEmpNo);
    when lFunc = 'D';
      DeleteEmployee(lEmpNo);
    when lFunc = 'V';
      ShowDetail('D': lEmpNo);
  endsl;

  if lFunc <> ' ';
    LoadSubfile();
  endif;
end-proc;

//==============================================================
// ShowDetail: muestra pantalla de detalle para editar o ver
//   pFunc = 'E' (Edit) | 'D' (Display)
//==============================================================
dcl-proc ShowDetail;
  dcl-pi *n;
    pFunc  char(1) value;
    pEmpNo char(6) value;
  end-pi;

  dcl-s lExit ind inz(*off);

  lExit = *off;

  exec sql
    select empno, coalesce(firstnme,' '), coalesce(midinit,' '),
           coalesce(lastname,' '), coalesce(workdept,'   '),
           coalesce(phoneno,'    '), coalesce(job,'        '),
           coalesce(salary,0), coalesce(sex,' '),
           coalesce(hiredate, current_date)
    into  :DEMNO, :DEFIRST, :DEINIT, :DELAST,
          :DEDEPT, :DEPHON,  :DEJOB, :DESAL,
          :DESEX, :DEHIRE
    from  cmpsys.employee
    where empno = :pEmpNo;

  if pFunc = 'E';
    DEFUNC = 'Editar';
  else;
    DEFUNC = 'Visualizar';
  endif;
  DEERR = ' ';

  dow not lExit;
    Write CLRSCR;
    Write DFOOTER;
    Exfmt DETALLE;

    select;
      when wFunKey = F12;
        lExit = *on;
      when wFunKey = ENTER and pFunc = 'E';
        if UpdateEmployee(pEmpNo);
          lExit = *on;
        else;
          DEERR = 'Error al actualizar. Verifique los datos.';
        endif;
      when wFunKey = ENTER and pFunc = 'D';
        lExit = *on;
    endsl;
  enddo;
end-proc;

//==============================================================
// UpdateEmployee: actualiza los campos editables del empleado
//==============================================================
dcl-proc UpdateEmployee;
  dcl-pi *n ind;
    pEmpNo char(6) value;
  end-pi;

  exec sql
    update cmpsys.employee
       set firstnme = :DEFIRST,
           midinit  = :DEINIT,
           lastname = :DELAST,
           workdept = :DEDEPT,
           phoneno  = :DEPHON,
           job      = :DEJOB,
           salary   = :DESAL,
           sex      = :DESEX
     where empno    = :pEmpNo;

  return sqlstate = '00000' or sqlstate = '02000';
end-proc;

//==============================================================
// DeleteEmployee: elimina un empleado por su numero
//==============================================================
dcl-proc DeleteEmployee;
  dcl-pi *n;
    pEmpNo char(6) value;
  end-pi;

  exec sql
    delete from cmpsys.employee
     where empno = :pEmpNo;
end-proc;

//==============================================================
// AddEmployee: genera ID, muestra detalle en modo Agregar
//==============================================================
dcl-proc AddEmployee;
  dcl-s lExit  ind    inz(*off);
  dcl-s lNewId char(6) inz('000001');

  lExit = *off;

  exec sql
    select right(repeat('0', 6) concat
                 trim(char(coalesce(max(int(empno)), 0) + 100)),
                 6)
      into :lNewId
      from cmpsys.employee;

  DEMNO   = lNewId;
  DEFIRST = ' ';
  DEINIT  = ' ';
  DELAST  = ' ';
  DEDEPT  = ' ';
  DEPHON  = ' ';
  DEJOB   = ' ';
  DESAL   = 0;
  DESEX   = ' ';
  DEHIRE  = %date();
  DEFUNC  = 'Agregar';
  DEERR   = ' ';

  dow not lExit;
    Write CLRSCR;
    Write DFOOTER;
    Exfmt DETALLE;

    select;
      when wFunKey = F12;
        lExit = *on;
      when wFunKey = ENTER;
        if %trim(DEFIRST) = '';
          DEERR = 'El nombre es obligatorio.';
        elseif %trim(DELAST) = '';
          DEERR = 'El apellido es obligatorio.';
        elseif InsertEmployee();
          lExit = *on;
        else;
          DEERR = 'Error al crear el empleado. Verifique los datos.';
        endif;
    endsl;
  enddo;
end-proc;

//==============================================================
// InsertEmployee: INSERT SQL del nuevo registro
//==============================================================
dcl-proc InsertEmployee;
  dcl-pi *n ind end-pi;

  exec sql
    insert into cmpsys.employee
      (empno, firstnme, midinit, lastname, workdept, phoneno,
       hiredate, job, edlevel, sex, birthdate, salary, bonus, comm)
    values
      (:DEMNO, :DEFIRST, :DEINIT, :DELAST, :DEDEPT, :DEPHON,
       :DEHIRE, :DEJOB, 12, :DESEX, current_date, :DESAL, 0, 0);

  return sqlstate = '00000';
end-proc;
