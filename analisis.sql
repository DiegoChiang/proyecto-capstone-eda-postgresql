/*
Proyecto Capstone: Analisis Exploratorio de Datos (EDA) en PostgreSQL
Archivo: analisis.sql

Requisito previo: ejecutar estructura.sql conectado a capstone_project.
Las ventas validas incluyen pedidos completados y enviados. Los cancelados se
conservan para auditoria, pero no representan ingresos ni unidades vendidas.
*/

/* ================================================================
   SECCIÓN 1. ETAPA DE LIMPIEZA Y VALIDACIÓN DE DATOS
   ================================================================ */

-- Medimos la ausencia de datos opcionales. Telefono y ciudad NULL significan
-- "dato no informado" y no justifican eliminar al cliente del analisis.
SELECT
    COUNT(*) FILTER (WHERE telefono IS NULL) AS clientes_sin_telefono,
    COUNT(*) FILTER (WHERE ciudad IS NULL) AS clientes_sin_ciudad
FROM clientes;

-- Los descuentos NULL representan operaciones sin promocion. Se transforman
-- en cero con COALESCE para evitar que el importe calculado se vuelva NULL.
SELECT
    COUNT(*) FILTER (WHERE descuento_pedido IS NULL) AS pedidos_sin_descuento,
    COUNT(*) FILTER (WHERE fecha_entrega IS NULL) AS pedidos_sin_fecha_entrega,
    COUNT(*) FILTER (WHERE estado = 'cancelado') AS pedidos_cancelados
FROM pedidos;

SELECT
    COUNT(*) FILTER (WHERE descuento_linea IS NULL) AS lineas_sin_descuento,
    COUNT(*) FILTER (WHERE precio_unitario IS NULL) AS precios_nulos,
    COUNT(*) FILTER (WHERE cantidad IS NULL) AS cantidades_nulas
FROM detalle_pedido;

-- Aunque las restricciones previenen valores invalidos, esta consulta sirve
-- como control de calidad si el origen de datos cambia o se desactivan reglas.
SELECT detalle_id, pedido_id, producto_id, cantidad, precio_unitario
FROM detalle_pedido
WHERE cantidad <= 0
   OR precio_unitario <= 0
   OR descuento_linea < 0
   OR descuento_linea > 100;

-- Verificamos que no haya pedidos anteriores al alta del cliente ni entregas
-- anteriores a la compra; cualquiera de estos casos indicaria fechas incoherentes.
SELECT
    p.pedido_id,
    c.cliente_id,
    c.fecha_registro,
    p.fecha_pedido,
    p.fecha_entrega
FROM pedidos AS p
INNER JOIN clientes AS c ON c.cliente_id = p.cliente_id
WHERE p.fecha_pedido::DATE < c.fecha_registro
   OR (p.fecha_entrega IS NOT NULL AND p.fecha_entrega < p.fecha_pedido::DATE);

-- Vista de validacion del importe por linea. NULLIF protege la division y CASE
-- etiqueta la calidad del registro sin modificar el dato original.
SELECT
    dp.detalle_id,
    ROUND(
        dp.cantidad * dp.precio_unitario
        * (1 - COALESCE(dp.descuento_linea, 0) / 100.0),
        2
    ) AS importe_neto_linea,
    CASE
        WHEN dp.descuento_linea IS NULL THEN 'sin promocion'
        WHEN dp.descuento_linea = 0 THEN 'descuento cero explicito'
        ELSE 'con promocion'
    END AS tratamiento_descuento,
    ROUND(dp.precio_unitario / NULLIF(pr.precio_lista, 0), 2) AS indice_precio_lista
FROM detalle_pedido AS dp
INNER JOIN productos AS pr ON pr.producto_id = dp.producto_id
ORDER BY dp.detalle_id;

/* ================================================================
   SECCION 2. TOP 5 CLIENTES POR GASTO TOTAL
   ================================================================ */

-- Calculamos el gasto real despues de descuentos de linea y de pedido. Se
-- excluyen cancelaciones porque no generan ingreso efectivo para el negocio.
SELECT
    c.cliente_id,
    c.nombre_completo,
    COUNT(DISTINCT p.pedido_id) AS pedidos_validos,
    ROUND(SUM(
        dp.cantidad * dp.precio_unitario
        * (1 - COALESCE(dp.descuento_linea, 0) / 100.0)
        * (1 - COALESCE(p.descuento_pedido, 0) / 100.0)
    ), 2) AS gasto_total
FROM clientes AS c
INNER JOIN pedidos AS p ON p.cliente_id = c.cliente_id
INNER JOIN detalle_pedido AS dp ON dp.pedido_id = p.pedido_id
WHERE p.estado <> 'cancelado'
GROUP BY c.cliente_id, c.nombre_completo
ORDER BY gasto_total DESC
LIMIT 5;

/* ================================================================
   SECCION 3. VENTAS TOTALES POR MES
   ================================================================ */

-- Agrupar por mes permite detectar cambios de demanda y planificar inventario.
SELECT
    DATE_TRUNC('month', p.fecha_pedido)::DATE AS mes,
    COUNT(DISTINCT p.pedido_id) AS pedidos_validos,
    ROUND(SUM(
        dp.cantidad * dp.precio_unitario
        * (1 - COALESCE(dp.descuento_linea, 0) / 100.0)
        * (1 - COALESCE(p.descuento_pedido, 0) / 100.0)
    ), 2) AS ventas_netas
FROM pedidos AS p
INNER JOIN detalle_pedido AS dp ON dp.pedido_id = p.pedido_id
WHERE p.estado <> 'cancelado'
GROUP BY DATE_TRUNC('month', p.fecha_pedido)
ORDER BY mes;

/* ================================================================
   SECCION 4. TRES PRODUCTOS MENOS VENDIDOS
   ================================================================ */

-- Definimos "menos vendido" como menor cantidad de unidades, una medida mas
-- adecuada que el ingreso para detectar productos de baja rotacion. LEFT JOIN
-- conserva tambien productos sin ventas, si se incorporan en el futuro.
SELECT
    pr.producto_id,
    pr.nombre_producto,
    pr.categoria,
    COALESCE(SUM(
        CASE WHEN p.estado <> 'cancelado' THEN dp.cantidad ELSE 0 END
    ), 0) AS unidades_vendidas
FROM productos AS pr
LEFT JOIN detalle_pedido AS dp ON dp.producto_id = pr.producto_id
LEFT JOIN pedidos AS p ON p.pedido_id = dp.pedido_id
GROUP BY pr.producto_id, pr.nombre_producto, pr.categoria
ORDER BY unidades_vendidas ASC, pr.nombre_producto ASC
LIMIT 3;

/* ================================================================
   SECCION 5. RANKING DE PRODUCTOS DENTRO DE CADA CATEGORIA
   ================================================================ */

-- El CTE calcula una sola fila por producto antes de aplicar RANK; asi evitamos
-- rankear lineas individuales o duplicar importes por la relacion uno-a-muchos.
WITH ventas_producto AS (
    SELECT
        pr.producto_id,
        pr.nombre_producto,
        pr.categoria,
        COALESCE(SUM(
            CASE
                WHEN p.estado <> 'cancelado' THEN
                    dp.cantidad * dp.precio_unitario
                    * (1 - COALESCE(dp.descuento_linea, 0) / 100.0)
                    * (1 - COALESCE(p.descuento_pedido, 0) / 100.0)
                ELSE 0
            END
        ), 0) AS ventas_netas
    FROM productos AS pr
    LEFT JOIN detalle_pedido AS dp ON dp.producto_id = pr.producto_id
    LEFT JOIN pedidos AS p ON p.pedido_id = dp.pedido_id
    GROUP BY pr.producto_id, pr.nombre_producto, pr.categoria
)
SELECT
    categoria,
    nombre_producto,
    ROUND(ventas_netas, 2) AS ventas_netas,
    RANK() OVER (
        PARTITION BY categoria
        ORDER BY ventas_netas DESC
    ) AS ranking_en_categoria
FROM ventas_producto
ORDER BY categoria, ranking_en_categoria, nombre_producto;

/* ================================================================
   SECCION 6. ANALISIS ADICIONALES
   ================================================================ */

-- 6.1 Ticket promedio por cliente. Primero consolidamos cada pedido para que
-- AVG opere sobre tickets completos y no sobre lineas individuales.
WITH totales_pedido AS (
    SELECT
        p.pedido_id,
        p.cliente_id,
        SUM(
            dp.cantidad * dp.precio_unitario
            * (1 - COALESCE(dp.descuento_linea, 0) / 100.0)
            * (1 - COALESCE(p.descuento_pedido, 0) / 100.0)
        ) AS total_pedido
    FROM pedidos AS p
    INNER JOIN detalle_pedido AS dp ON dp.pedido_id = p.pedido_id
    WHERE p.estado <> 'cancelado'
    GROUP BY p.pedido_id, p.cliente_id
)
SELECT
    c.cliente_id,
    c.nombre_completo,
    COUNT(tp.pedido_id) AS cantidad_pedidos,
    ROUND(AVG(tp.total_pedido), 2) AS ticket_promedio
FROM clientes AS c
INNER JOIN totales_pedido AS tp ON tp.cliente_id = c.cliente_id
GROUP BY c.cliente_id, c.nombre_completo
ORDER BY ticket_promedio DESC, c.nombre_completo;

-- 6.2 Ingreso y participacion por categoria. La ventana usa el total agregado
-- para mostrar que categorias concentran el ingreso sin una consulta separada.
WITH ventas_categoria AS (
    SELECT
        pr.categoria,
        SUM(
            dp.cantidad * dp.precio_unitario
            * (1 - COALESCE(dp.descuento_linea, 0) / 100.0)
            * (1 - COALESCE(p.descuento_pedido, 0) / 100.0)
        ) AS ventas_netas
    FROM productos AS pr
    INNER JOIN detalle_pedido AS dp ON dp.producto_id = pr.producto_id
    INNER JOIN pedidos AS p ON p.pedido_id = dp.pedido_id
    WHERE p.estado <> 'cancelado'
    GROUP BY pr.categoria
)
SELECT
    categoria,
    ROUND(ventas_netas, 2) AS ventas_netas,
    ROUND(100 * ventas_netas / NULLIF(SUM(ventas_netas) OVER (), 0), 2)
        AS porcentaje_ingresos
FROM ventas_categoria
ORDER BY ventas_netas DESC;

-- 6.3 Recurrencia de clientes. Este indicador separa compradores recurrentes
-- de compradores de una sola vez para orientar acciones de fidelizacion.
SELECT
    c.cliente_id,
    c.nombre_completo,
    COUNT(DISTINCT p.pedido_id) AS pedidos_validos,
    CASE
        WHEN COUNT(DISTINCT p.pedido_id) >= 3 THEN 'alta recurrencia'
        WHEN COUNT(DISTINCT p.pedido_id) = 2 THEN 'recurrente'
        ELSE 'compra unica'
    END AS segmento_recurrencia
FROM clientes AS c
INNER JOIN pedidos AS p ON p.cliente_id = c.cliente_id
WHERE p.estado <> 'cancelado'
GROUP BY c.cliente_id, c.nombre_completo
ORDER BY pedidos_validos DESC, c.nombre_completo;

-- 6.4 Evolucion mensual de pedidos y unidades. Complementa el ingreso mensual
-- con volumen transaccional para distinguir precio de demanda real.
SELECT
    DATE_TRUNC('month', p.fecha_pedido)::DATE AS mes,
    COUNT(DISTINCT p.pedido_id) AS pedidos_validos,
    SUM(dp.cantidad) AS unidades_vendidas,
    ROUND(AVG(dp.cantidad), 2) AS unidades_promedio_por_linea
FROM pedidos AS p
INNER JOIN detalle_pedido AS dp ON dp.pedido_id = p.pedido_id
WHERE p.estado <> 'cancelado'
GROUP BY DATE_TRUNC('month', p.fecha_pedido)
ORDER BY mes;
