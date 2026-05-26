# demoas400

Repositorio consolidado con ejemplos y activos de desarrollo para AS/400 e IBM i.

## Contexto

Este repositorio agrupa, en un solo lugar, contenido técnico importado desde un workspace local con proyectos orientados a:

- RPGLE y SQLRPGLE
- CL/CLLE y objetos de sistema IBM i
- DDS y SQL DDL
- utilidades, APIs y ejemplos de servicios

El objetivo es facilitar revisión, consulta, versionado y publicación de material IBM i en una estructura unificada.

## Estructura Actual

- [ibmi-company_system](ibmi-company_system): sistema de ejemplo con fuentes RPGLE, SQLRPGLE, DDS, SQL scripts y pruebas.
- [IBM-i-RPG-Free-CLP-Code](IBM-i-RPG-Free-CLP-Code): colección extensa de utilidades y ejemplos IBM i (APIs, subfiles 5250, service programs, impresión, etc.).
- [intERPrise](intERPrise): solución empresarial multi-módulo con componentes DB, transporte, UI y artefactos asociados.

## Alcance

- Repositorio orientado a referencia técnica y preservación de fuentes.
- Puede contener código de distintos estilos, épocas y convenciones de nomenclatura.
- Se priorizó conservar la estructura original de cada proyecto importado.

## Notas Operativas

- Las carpetas de control de repositorios origen fueron excluidas al importar para evitar repos anidados.
- Los módulos se incorporaron por commits separados para mejorar trazabilidad.
- El contenido está publicado en la rama main.

## Recomendaciones

- Mantener cambios nuevos en commits por módulo o carpeta principal.
- Documentar en este README cualquier nueva importación significativa.
- Si se agregan scripts de build/deploy, incluir sección de uso por plataforma.
