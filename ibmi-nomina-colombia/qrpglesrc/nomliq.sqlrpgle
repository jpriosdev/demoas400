**free
ctl-opt nomain;

/copy 'qrpgleref/nomina.rpgleinc'

// ─── calcularLiquidacion ──────────────────────────────────────────────────────
// Calcula todos los conceptos de una quincena colombiana para un empleado.
// Retorna nomina_liq_t con found=*off si el empleado no existe en NOMINA_EMP.
dcl-proc calcularLiquidacion export;
  dcl-pi *n like(nomina_liq_t);
    empno            char(6)      const;
    periodo_id       char(8)      const;
    dias_trab        packed(3:0)  const;
    horas_ext_diur   packed(5:2)  const;
    horas_ext_noc    packed(5:2)  const;
    horas_ext_fest_d packed(5:2)  const;
    horas_ext_fest_n packed(5:2)  const;
    horas_rec_noc    packed(5:2)  const;
    otras_ded        packed(11:2) const;
  end-pi;

  dcl-ds liq     likeds(nomina_liq_t) inz;
  dcl-s  hora_ord packed(11:4);
  dcl-s  ibc      packed(11:2);
  dcl-s  arl_pct  packed(7:5);
  dcl-s  nombre   varchar(50);

  // Obtener datos laborales del empleado
  exec sql
    select ne.salario_basico,
           ne.nivel_riesgo,
           trim(e.firstnme) concat ' ' concat trim(e.lastname)
      into :liq.salario_basico,
           :liq.nivel_riesgo,
           :nombre
      from nomina_emp ne
      join employee   e  on e.empno = ne.empno
     where ne.empno  = :empno
       and ne.activo = 'S';

  if sqlcode <> 0;
    liq.found = *off;
    return liq;
  endif;

  liq.found      = *on;
  liq.empno      = empno;
  liq.periodo_id = periodo_id;
  liq.nombre     = nombre;
  liq.dias_trab  = dias_trab;
  liq.horas_ext_diur   = horas_ext_diur;
  liq.horas_ext_noc    = horas_ext_noc;
  liq.horas_ext_fest_d = horas_ext_fest_d;
  liq.horas_ext_fest_n = horas_ext_fest_n;
  liq.horas_rec_noc    = horas_rec_noc;
  liq.otras_ded        = otras_ded;

  // ── Devengados ──────────────────────────────────────────────────────────────
  // Colombia: mes = 30 dias siempre (art. 134 CST)
  liq.salario_quincena = (liq.salario_basico / DIAS_MES) * dias_trab;

  // Auxilio de transporte: aplica si salario <= 2 SMMLV (art. 7 Ley 1a/1963)
  if liq.salario_basico <= (2 * SMMLV);
    liq.aux_transporte = AUX_TRANSPORTE / 2;  // mitad por quincena
  else;
    liq.aux_transporte = 0;
  endif;

  // Hora ordinaria base para horas extras
  hora_ord = liq.salario_basico / DIAS_MES / HORAS_DIA;

  liq.valor_hext =
      (horas_ext_diur   * hora_ord * (1 + REC_HED))  +
      (horas_ext_noc    * hora_ord * (1 + REC_HEN))  +
      (horas_ext_fest_d * hora_ord * (1 + REC_HEFD)) +
      (horas_ext_fest_n * hora_ord * (1 + REC_HEFN)) +
      (horas_rec_noc    * hora_ord * REC_RNO);

  liq.total_devengado = liq.salario_quincena + liq.aux_transporte + liq.valor_hext;

  // ── IBC (Ingreso Base de Cotizacion) ────────────────────────────────────────
  // Excluye auxilio de transporte. Min = SMMLV/2, Max = 25 SMMLV/2
  ibc = liq.salario_quincena + liq.valor_hext;
  if ibc < (SMMLV / 2);
    ibc = SMMLV / 2;
  endif;
  if ibc > (SMMLV * 25 / 2);
    ibc = SMMLV * 25 / 2;
  endif;

  // ── Deducciones empleado ────────────────────────────────────────────────────
  liq.salud_emp       = ibc * PCT_SALUD_EMP;
  liq.pension_emp     = ibc * PCT_PENSION_EMP;
  liq.retencion_fte   = 0;  // Retencion en fuente: fase futura
  liq.total_deduccion = liq.salud_emp + liq.pension_emp +
                        liq.retencion_fte + otras_ded;
  liq.neto_pagar      = liq.total_devengado - liq.total_deduccion;

  // ── Aportes empleador ───────────────────────────────────────────────────────
  arl_pct = getArlPct(liq.nivel_riesgo);
  liq.salud_emp_comp   = ibc * PCT_SALUD_COMP;
  liq.pension_emp_comp = ibc * PCT_PENSION_COMP;
  liq.arl              = ibc * arl_pct;
  liq.sena             = ibc * PCT_SENA;
  liq.icbf             = ibc * PCT_ICBF;
  liq.caja_comp        = ibc * PCT_CAJA;
  liq.total_aportes_emp = liq.salud_emp_comp + liq.pension_emp_comp +
                          liq.arl + liq.sena + liq.icbf + liq.caja_comp;

  // ── Provisiones prestaciones sociales ───────────────────────────────────────
  // Base cesantias/prima incluye auxilio transporte (art. 249 CST)
  // Vacaciones: solo sobre salario (art. 192 CST)
  liq.prov_cesantias  = (liq.salario_quincena + liq.aux_transporte) * PCT_CESANTIAS;
  liq.prov_int_ces    = liq.prov_cesantias * PCT_INT_CES;
  liq.prov_prima      = (liq.salario_quincena + liq.aux_transporte) * PCT_PRIMA;
  liq.prov_vacaciones = liq.salario_quincena * PCT_VACACIONES;
  liq.total_provisiones = liq.prov_cesantias + liq.prov_int_ces +
                          liq.prov_prima + liq.prov_vacaciones;

  // Costo total empresa = devengado + aportes + provisiones
  liq.costo_total = liq.total_devengado + liq.total_aportes_emp + liq.total_provisiones;

  return liq;
end-proc;

// ─── guardarLiquidacion ───────────────────────────────────────────────────────
// Inserta o actualiza la liquidacion en NOMINA_LIQ.
// Retorna *on si sqlcode = 0.
dcl-proc guardarLiquidacion export;
  dcl-pi *n ind;
    liq likeds(nomina_liq_t) const;
  end-pi;

  dcl-s cnt int(5);

  exec sql select count(*) into :cnt
             from nomina_liq
            where empno      = :liq.empno
              and periodo_id = :liq.periodo_id;

  if cnt > 0;
    exec sql
      update nomina_liq set
        dias_trab        = :liq.dias_trab,
        horas_ext_diur   = :liq.horas_ext_diur,
        horas_ext_noc    = :liq.horas_ext_noc,
        horas_ext_fest_d = :liq.horas_ext_fest_d,
        horas_ext_fest_n = :liq.horas_ext_fest_n,
        horas_rec_noc    = :liq.horas_rec_noc,
        otras_ded        = :liq.otras_ded,
        salario_quincena = :liq.salario_quincena,
        aux_transporte   = :liq.aux_transporte,
        valor_hext       = :liq.valor_hext,
        total_devengado  = :liq.total_devengado,
        salud_emp        = :liq.salud_emp,
        pension_emp      = :liq.pension_emp,
        retencion_fte    = :liq.retencion_fte,
        total_deduccion  = :liq.total_deduccion,
        neto_pagar       = :liq.neto_pagar,
        salud_emp_comp   = :liq.salud_emp_comp,
        pension_emp_comp = :liq.pension_emp_comp,
        arl              = :liq.arl,
        sena             = :liq.sena,
        icbf             = :liq.icbf,
        caja_comp        = :liq.caja_comp,
        total_aportes_emp  = :liq.total_aportes_emp,
        prov_cesantias   = :liq.prov_cesantias,
        prov_int_ces     = :liq.prov_int_ces,
        prov_prima       = :liq.prov_prima,
        prov_vacaciones  = :liq.prov_vacaciones,
        total_provisiones  = :liq.total_provisiones,
        costo_total      = :liq.costo_total,
        estado           = 'CA',
        ts_liquidado     = current_timestamp
      where empno      = :liq.empno
        and periodo_id = :liq.periodo_id;
  else;
    exec sql
      insert into nomina_liq (
        periodo_id, empno,
        dias_trab, horas_ext_diur, horas_ext_noc,
        horas_ext_fest_d, horas_ext_fest_n, horas_rec_noc, otras_ded,
        salario_quincena, aux_transporte, valor_hext, total_devengado,
        salud_emp, pension_emp, retencion_fte, total_deduccion, neto_pagar,
        salud_emp_comp, pension_emp_comp, arl, sena, icbf, caja_comp,
        total_aportes_emp,
        prov_cesantias, prov_int_ces, prov_prima, prov_vacaciones,
        total_provisiones, costo_total, estado
      ) values (
        :liq.periodo_id, :liq.empno,
        :liq.dias_trab, :liq.horas_ext_diur, :liq.horas_ext_noc,
        :liq.horas_ext_fest_d, :liq.horas_ext_fest_n, :liq.horas_rec_noc,
        :liq.otras_ded,
        :liq.salario_quincena, :liq.aux_transporte, :liq.valor_hext,
        :liq.total_devengado,
        :liq.salud_emp, :liq.pension_emp, :liq.retencion_fte,
        :liq.total_deduccion, :liq.neto_pagar,
        :liq.salud_emp_comp, :liq.pension_emp_comp, :liq.arl,
        :liq.sena, :liq.icbf, :liq.caja_comp, :liq.total_aportes_emp,
        :liq.prov_cesantias, :liq.prov_int_ces, :liq.prov_prima,
        :liq.prov_vacaciones, :liq.total_provisiones, :liq.costo_total, 'CA'
      );
  endif;

  return sqlcode = 0;
end-proc;

// ─── getArlPct ────────────────────────────────────────────────────────────────
// Retorna la tasa ARL segun nivel de riesgo (Decreto 1607/2002).
dcl-proc getArlPct export;
  dcl-pi *n packed(7:5);
    nivel_riesgo packed(1:0) const;
  end-pi;

  select;
    when nivel_riesgo = 1; return ARL_N1;
    when nivel_riesgo = 2; return ARL_N2;
    when nivel_riesgo = 3; return ARL_N3;
    when nivel_riesgo = 4; return ARL_N4;
    when nivel_riesgo = 5; return ARL_N5;
    other;                 return ARL_N1;
  endsl;
end-proc;
