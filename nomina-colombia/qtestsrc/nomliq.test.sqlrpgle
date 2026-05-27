**free
ctl-opt nomain ccsidcvt(*excp) ccsid(*char : *jobrun) BNDDIR('NOM');

/include qinclude,TESTCASE
/copy 'qrpgleref/nomina.rpgleinc'

// ─── Setup: datos de prueba aislados ──────────────────────────────────────────
dcl-proc setUpSuite export;
  setupMockTable('EMPLOYEE');
  exec sql insert into employee (empno, firstnme, midinit, lastname, edlevel)
           values ('T00001', 'Ana',  'M', 'Torres', 1),
                  ('T00002', 'Luis', 'A', 'Gomez',  1);

  setupMockTable('NOMINA_EMP');
  // Empleado con salario mínimo → aplica auxilio transporte
  exec sql insert into nomina_emp (empno, tipo_contrato, fecha_ingreso,
                                    salario_basico, nivel_riesgo, activo)
           values ('T00001', 'IN', '2020-01-15', 1300000, 1, 'S');
  // Empleado con salario > 2 SMMLV → NO aplica auxilio transporte
  exec sql insert into nomina_emp (empno, tipo_contrato, fecha_ingreso,
                                    salario_basico, nivel_riesgo, activo)
           values ('T00002', 'IN', '2019-03-01', 3000000, 3, 'S');

  setupMockTable('NOMINA_PERIODO');
  exec sql insert into nomina_periodo (periodo_id, anio, mes, quincena,
                                        fecha_ini, fecha_fin, estado)
           values ('20260501', 2026, 5, 1, '2026-05-01', '2026-05-15', 'AB');
end-proc;

// ─── Test 1: SMMLV, 15 días, sin horas extras ────────────────────────────────
// Salario: 1.300.000 → quincena: 650.000
// Aux transporte: 81.000 (mitad de 162.000)
// Salud emp: 650.000 * 4% = 26.000
// Pensión emp: 650.000 * 4% = 26.000
// Neto: 650.000 + 81.000 - 26.000 - 26.000 = 679.000
dcl-proc test_saMinimo_sinExtras export;
  dcl-ds actual likeds(nomina_liq_t) inz;

  actual = calcularLiquidacion('T00001' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(actual.found            : 'found debe ser *on');
  assert(actual.salario_quincena = 650000 : 'salario_quincena');
  assert(actual.aux_transporte   =  81000 : 'aux_transporte');
  assert(actual.valor_hext       =      0 : 'valor_hext');
  assert(actual.total_devengado  = 731000 : 'total_devengado');
  assert(actual.salud_emp        =  26000 : 'salud_emp 4%');
  assert(actual.pension_emp      =  26000 : 'pension_emp 4%');
  assert(actual.neto_pagar       = 679000 : 'neto_pagar');
end-proc;

// ─── Test 2: Salario > 2 SMMLV → sin aux transporte ──────────────────────────
// Salario: 3.000.000 → quincena: 1.500.000
// Sin aux transporte (salario > 2 * 1.300.000 = 2.600.000)
// Neto: 1.500.000 - 60.000 - 60.000 = 1.380.000
dcl-proc test_salarioAlto_sinAuxTransporte export;
  dcl-ds actual likeds(nomina_liq_t) inz;

  actual = calcularLiquidacion('T00002' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(actual.found          : 'found debe ser *on');
  assert(actual.aux_transporte = 0       : 'sin aux transporte');
  assert(actual.salud_emp      = 60000   : 'salud_emp 4% de 1500000');
  assert(actual.pension_emp    = 60000   : 'pension_emp 4% de 1500000');
  assert(actual.neto_pagar     = 1380000 : 'neto_pagar');
end-proc;

// ─── Test 3: Horas extras diurnas ─────────────────────────────────────────────
// Salario: 1.300.000 → hora ordinaria: 1.300.000 / 30 / 8 = 5.416,67
// 4 HED: 4 * hora_ord * 1.25
dcl-proc test_horasExtras_diurnas export;
  dcl-ds actual   likeds(nomina_liq_t) inz;
  dcl-s  hora_ord packed(11:4);
  dcl-s  expected packed(11:2);

  hora_ord = 1300000 / 30 / 8;
  expected = 4 * hora_ord * (1 + 0.25);

  actual = calcularLiquidacion('T00001' : '20260501' : 15 :
                                4 : 0 : 0 : 0 : 0 : 0);

  assert(actual.found      : 'found');
  assert(actual.valor_hext = expected : 'valor HED 4 horas');
end-proc;

// ─── Test 4: Aportes empleador nivel riesgo 1 ─────────────────────────────────
// IBC quincena: 650.000
// Salud comp:  650.000 * 8.5%  = 55.250
// Pensión comp: 650.000 * 12%  = 78.000
// SENA:         650.000 * 2%   = 13.000
// ICBF:         650.000 * 3%   = 19.500
// Caja:         650.000 * 4%   = 26.000
dcl-proc test_aportesEmpleador_nivelRiesgo1 export;
  dcl-ds actual likeds(nomina_liq_t) inz;

  actual = calcularLiquidacion('T00001' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(actual.salud_emp_comp   = 55250 : 'salud_emp_comp 8.5%');
  assert(actual.pension_emp_comp = 78000 : 'pension_emp_comp 12%');
  assert(actual.sena             = 13000 : 'sena 2%');
  assert(actual.icbf             = 19500 : 'icbf 3%');
  assert(actual.caja_comp        = 26000 : 'caja 4%');
end-proc;

// ─── Test 5: Provisiones prestaciones sociales ────────────────────────────────
// Base cesantías/prima = salario_quincena + aux_transporte = 650.000 + 81.000 = 731.000
// prov_cesantias: 731.000 * 8.33%
// prov_int_ces:   prov_cesantias * 1%
// prov_prima:     igual a prov_cesantias
// prov_vacaciones: 650.000 * 4.17% (solo salario, sin aux transporte)
dcl-proc test_provisiones_prestaciones export;
  dcl-ds actual   likeds(nomina_liq_t) inz;
  dcl-s  base     packed(11:2);
  dcl-s  exp_ces  packed(9:2);
  dcl-s  exp_vac  packed(9:2);

  base    = 650000 + 81000;
  exp_ces = base * PCT_CESANTIAS;
  exp_vac = 650000 * PCT_VACACIONES;

  actual = calcularLiquidacion('T00001' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(actual.prov_cesantias  = exp_ces              : 'prov_cesantias');
  assert(actual.prov_int_ces    = exp_ces * PCT_INT_CES : 'prov_int_ces 1%');
  assert(actual.prov_prima      = exp_ces              : 'prov_prima = prov_cesantias');
  assert(actual.prov_vacaciones = exp_vac              : 'prov_vacaciones');
end-proc;

// ─── Test 6: Empleado no encontrado → found = *off ────────────────────────────
dcl-proc test_empleadoNoExiste_found_off export;
  dcl-ds actual likeds(nomina_liq_t) inz;

  actual = calcularLiquidacion('XXXXXX' : '20260501' : 15 :
                                0 : 0 : 0 : 0 : 0 : 0);

  assert(NOT actual.found : 'found debe ser *off para empleado inexistente');
end-proc;
