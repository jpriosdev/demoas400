<map version="1.0.1">
  <node TEXT="demoas400 - arbol funcional de negocio">
    <node TEXT="1. Operacion de servicios de transporte (intERPrise)">
      <node TEXT="1.1 Navegacion por menus">
        <node TEXT="IRPTMAIN (menu principal)">
          <node TEXT="Opcion 1 -> IRPTOPS (operaciones)"/>
          <node TEXT="Opcion 2 -> IRPTCFG (configuracion)"/>
        </node>
      </node>
      <node TEXT="1.2 Configuracion de servidor">
        <node TEXT="IRPTCFG -> WRKIRPTCFG -> IRP1000"/>
        <node TEXT="Gestion de parametros y defaults del servidor"/>
      </node>
      <node TEXT="1.3 Operacion del servidor">
        <node TEXT="IRPTOPS opcion 1 -> CALL IRP2001">
          <node TEXT="IRP2001 -> STRSBS IRPTSBS + SBMJOB IRP0000"/>
          <node TEXT="Inicio de listeners y workers"/>
        </node>
        <node TEXT="IRPTOPS opcion 2 -> CALL IRP0002 (fin/gestion workers)"/>
        <node TEXT="IRPTOPS opcion 3 -> CALL IRP0004 (work with SessionIDs)"/>
      </node>
      <node TEXT="1.4 Soporte operativo">
        <node TEXT="Display messages -> DSPMSG IRPTMSGQ"/>
        <node TEXT="Work with server jobs -> WRKACTJOB SBS(IRPTSBS)"/>
      </node>
      <node TEXT="1.5 Pruebas funcionales de transporte">
        <node TEXT="Comando SVRTEST -> programa SVRTEST"/>
      </node>
    </node>

    <node TEXT="2. Gestion comercial de clientes (5250)">
      <node TEXT="2.1 Consulta y seleccion de clientes">
        <node TEXT="PMTCUSTR (subfile de consulta/prompt)"/>
      </node>
      <node TEXT="2.2 Mantenimiento de cliente">
        <node TEXT="PMTCUSTR -> MTNCUSTR (alta/cambio de datos)"/>
      </node>
      <node TEXT="2.3 Catalogo de estados">
        <node TEXT="PMTCUSTR y MTNCUSTR -> PMTSTATER (prompt de estado)"/>
      </node>
      <node TEXT="2.4 Carga inicial o masiva">
        <node TEXT="LOADCUST / LOADCUST2 -> LOADCUSTR"/>
      </node>
      <node TEXT="2.5 Dependencias tecnicas relevantes">
        <node TEXT="UTIL_BND, SQL_BND y SRV_BASE36"/>
      </node>
    </node>

    <node TEXT="3. Control de concurrencia y bloqueos">
      <node TEXT="3.1 Locks de objetos (batch y operacion)">
        <node TEXT="GETOBJUSR (CMD) -> GETOBJUC (CLLE) -> GETOBJUR (RPGLE/SQLRPGLE)"/>
        <node TEXT="Version API clasica y version SQL (QSYS2)"/>
      </node>
      <node TEXT="3.2 Locks de registros en pantallas interactivas">
        <node TEXT="RCDLCKDSP para informar quien tiene el bloqueo"/>
      </node>
    </node>

    <node TEXT="4. Fechas de negocio y calendario">
      <node TEXT="4.1 Ajuste de fechas para CL">
        <node TEXT="DATEADJ (CMD) -> DATEADJR"/>
        <node TEXT="Suma/resta de dias, meses y anios"/>
      </node>
      <node TEXT="4.2 Conversion de fechas legacy en SQL">
        <node TEXT="DATE_UDF (UDFs RPG para SQL)"/>
      </node>
    </node>

    <node TEXT="5. Impresion y reportes operativos">
      <node TEXT="5.1 Impresion desde CL">
        <node TEXT="PRTLN (CMD) -> PRTLNC -> PRT"/>
      </node>
      <node TEXT="5.2 Impresion en RPG free">
        <node TEXT="Tecnicas sin O-specs y sin printer file externo"/>
      </node>
    </node>

    <node TEXT="6. Calidad de direccion y contacto">
      <node TEXT="6.1 Validacion USPS">
        <node TEXT="USADRVAL (service) usando QSYS2.HTTP_GET"/>
        <node TEXT="Integrable al mantenimiento de clientes"/>
      </node>
    </node>

    <node TEXT="7. Identificadores y codificacion de negocio">
      <node TEXT="7.1 Secuencias alfanumericas base36">
        <node TEXT="SRV_BASE36 para incrementar claves alfanumericas"/>
      </node>
    </node>

    <node TEXT="8. Productividad y soporte al desarrollo">
      <node TEXT="8.1 Sesiones de trabajo para desarrollador">
        <node TEXT="GRP_JOB (group jobs, ATTN selector)"/>
      </node>
      <node TEXT="8.2 Utilidades operativas">
        <node TEXT="Utils (QRY, RC y comandos de apoyo)"/>
      </node>
      <node TEXT="8.3 Plantillas y estandares de codigo SQL RPG">
        <node TEXT="SQL_SKELETON"/>
      </node>
      <node TEXT="8.4 Analisis de dependencias entre programas">
        <node TEXT="PGM_REFS (procedimiento SQL recursivo)"/>
      </node>
    </node>
  </node>
</map>
