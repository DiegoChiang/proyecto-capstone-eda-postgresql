# Proyecto Capstone: Análisis Exploratorio de Datos con PostgreSQL

## Descripción

Este proyecto reproduce de principio a fin el trabajo de un analista de datos sobre un e-commerce ficticio: modela una base relacional, carga datos de prueba, valida su calidad, transforma valores opcionales y responde preguntas comerciales mediante SQL. El conjunto de datos es autocontenido y no requiere archivos ni servicios externos.

## Problema de negocio

Una empresa de comercio electrónico necesita comprender el comportamiento de sus clientes y el desempeño de su catálogo para tomar mejores decisiones de fidelización, promociones e inventario. El análisis busca responder:

- ¿Quiénes son los clientes más valiosos?
- ¿Cómo evolucionan las ventas netas por mes?
- ¿Qué productos tienen menor rotación?
- ¿Qué categorías generan mayores ingresos?
- ¿Cómo se posiciona cada producto dentro de su categoría?
- ¿Cuál es el ticket promedio y qué clientes son recurrentes?

## Objetivos del análisis

- Construir un modelo relacional consistente para clientes, productos y transacciones.
- Calcular ventas reales considerando cantidad, precio y descuentos acumulados.
- Separar pedidos cancelados de las ventas válidas sin perder su trazabilidad.
- Detectar valores ausentes e inconsistencias potenciales antes de analizar.
- Identificar concentración de ingresos, tendencias mensuales y baja rotación.
- Demostrar consultas con agregaciones, CTE, funciones de fecha y ventanas.

## Modelo de datos

```text
clientes
   |
   | 1:N
   v
pedidos
   |
   | 1:N
   v
detalle_pedido
   |
   | N:1
   v
productos
```

- **clientes:** datos de identificación, contacto, ciudad, fecha de alta y estado del cliente.
- **productos:** catálogo, categoría, precio de lista, costo unitario y disponibilidad.
- **pedidos:** cabecera de cada compra; relaciona al cliente con fecha, estado, canal, descuento general y entrega.
- **detalle_pedido:** líneas de producto de cada pedido, con cantidad, precio histórico y descuento específico.

Las claves foráneas implementan las relaciones reales y la restricción única `(pedido_id, producto_id)` evita duplicar un producto dentro del mismo pedido. Los precios se guardan como `NUMERIC`, no como valores de punto flotante.

## Tecnologías utilizadas

- PostgreSQL
- SQL
- pgAdmin (recomendado para ejecución visual)
- `psql` (alternativa por terminal)

## Estructura del repositorio

```text
.
├── estructura.sql  # Tablas, restricciones, relaciones y datos de prueba
├── analisis.sql    # Limpieza, validaciones y análisis de negocio
└── README.md       # Documentación, ejecución e interpretación
```

## Configuración

### Opción A: pgAdmin

1. En pgAdmin, conéctese al servidor PostgreSQL.
2. Haga clic derecho en **Databases > Create > Database**.
3. Asigne el nombre `capstone_project` y guarde.
4. Seleccione `capstone_project` y abra **Query Tool**.
5. Abra y ejecute primero `estructura.sql`. Las cuatro consultas finales deben mostrar 15 clientes, 12 productos, 36 pedidos y 72 líneas.
6. Abra y ejecute después `analisis.sql`. Cada sección devuelve un resultado independiente.

### Opción B: psql

Desde la carpeta del proyecto, reemplace `usuario` por un rol válido de PostgreSQL:

```bash
createdb -U usuario capstone_project
psql -U usuario -d capstone_project -f estructura.sql
psql -U usuario -d capstone_project -f analisis.sql
```

`CREATE DATABASE` debe ejecutarse conectado a otra base y fuera de una transacción. Por eso `estructura.sql` lo incluye como instrucción comentada y se ejecuta una vez establecida la conexión a `capstone_project`.

## Limpieza de datos

Los `NULL` fueron incluidos de forma deliberada únicamente en campos opcionales. Un teléfono o una ciudad ausente significan “dato no informado”; una fecha de entrega ausente es válida para pedidos enviados o cancelados. No se eliminan esos registros, porque continúan siendo útiles.

En los descuentos, `NULL` significa que no se aplicó promoción. Las fórmulas usan `COALESCE(descuento, 0)` para convertirlo en cero y evitar que el importe neto completo resulte `NULL`. Las consultas también buscan precios o cantidades inválidas, fechas incoherentes y valores ausentes en columnas críticas. Las restricciones de la base previenen esos problemas, mientras las validaciones permiten detectarlos si cambia la fuente.

Para todas las métricas de venta se consideran los estados `completado` y `enviado`; los pedidos `cancelado` se conservan para auditoría, pero se excluyen de ingresos y unidades vendidas.

## Consultas realizadas

1. Perfil de valores `NULL`, verificación de columnas críticas, precios, cantidades y fechas.
2. Cálculo del importe neto por línea y clasificación del tratamiento de descuentos.
3. Top 5 de clientes por gasto neto total.
4. Ventas netas y cantidad de pedidos por mes mediante `DATE_TRUNC`.
5. Tres productos de menor rotación, medida en unidades vendidas.
6. Ranking de productos por ingreso dentro de cada categoría mediante `RANK()`.
7. Ticket promedio por cliente, consolidando primero el total de cada pedido.
8. Ingreso y porcentaje de participación por categoría.
9. Segmentación de clientes según recurrencia.
10. Evolución mensual de pedidos y unidades vendidas.

## Hallazgos principales

Los resultados se obtienen del dataset incluido y consideran descuentos de línea y de pedido:

- **Concentración por cliente:** Ana Torres lidera con S/ 16 955,50 de gasto neto. Los cinco clientes con mayor gasto reúnen el 61,96 % de los S/ 68 419,30 vendidos, por lo que una estrategia de fidelización sobre este grupo puede proteger una parte relevante del ingreso.
- **Categoría dominante:** Tecnología genera S/ 38 249,00 y concentra el 55,90 % de la facturación neta. El alto precio de laptops y smartphones explica que lidere en ingreso sin ser la categoría con más unidades.
- **Baja rotación:** la Impresora Multifunción registra 3 unidades y la Cafetera Programable 4. Aspiradora Compacta y Hub USB-C empatan después con 5 unidades; el `LIMIT 3` devuelve la Aspiradora por el desempate alfabético definido en la consulta.
- **Evolución mensual:** junio es el mes de mayor ingreso, con S/ 13 247,80, mientras febrero presenta el menor, con S/ 9 930,75. La diferencia entre ambos es de aproximadamente 33,4 %, pese a que ambos contienen seis pedidos válidos, lo que apunta a un cambio en la mezcla y el valor de los productos comprados.
- **Recurrencia:** Ana Torres reúne cinco pedidos válidos; Carlos Mendoza cuatro; Luisa Fernández y María Quispe tres cada una. Estos clientes justifican acciones de fidelización diferenciadas.

## Conclusiones

El modelo permite relacionar valor del cliente, evolución temporal y desempeño del catálogo en una única fuente consistente. Considerar ambos niveles de descuento evita sobreestimar ingresos, y separar cancelaciones conserva la trazabilidad sin distorsionar los indicadores. La combinación de ingreso y unidades aporta una visión más útil: un producto puede facturar mucho por su precio y, al mismo tiempo, presentar menor rotación física.

## Posibles mejoras

- Sustituir el dataset ficticio por datos reales y automatizar su carga.
- Incorporar índices en fechas y claves de búsqueda al crecer el volumen.
- Crear vistas materializadas para indicadores consultados con frecuencia.
- Añadir visualizaciones o un dashboard en Power BI, Tableau o Metabase.
- Analizar cohortes, retención, margen bruto y rentabilidad por canal.
- Incorporar inventario, devoluciones, métodos de pago y datos geográficos.
