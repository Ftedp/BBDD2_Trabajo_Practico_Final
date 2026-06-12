-- ============================================================
-- DATA WAREHOUSE - THE DRINKING COMPANY (TDC)
-- Script de creación de tablas en SQL Server
-- ============================================================
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'TDC_DW')
BEGIN
    ALTER DATABASE TDC_DW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE TDC_DW;
END
GO
CREATE DATABASE TDC_DW;
GO

USE TDC_DW;
GO

-- ============================================================
-- DIMENSIONES
-- ============================================================

-- DIM_FECHA
CREATE TABLE DIM_FECHA (
    fecha_nro       INT             NOT NULL,
	fecha_completa  DATE            NULL,
    dia             INT             NOT NULL,
    dia_sem_nro     INT             NOT NULL,
    dia_sem_nomb    VARCHAR(20)     NOT NULL,
    mes             INT             NOT NULL,
    mes_nombre      VARCHAR(20)     NOT NULL,
    trimestre       INT             NOT NULL,
    semestre        INT             NOT NULL,
    anio            INT             NOT NULL,
    feriado         BIT             NOT NULL DEFAULT 0,
    CONSTRAINT PK_DIM_FECHA PRIMARY KEY (fecha_nro)
);
GO

-- DIM_CLIENTE
-- La geografía del cliente está desnormalizada.
-- DIM_GEOGRAFIA es una dimensión separada usada solo para el punto de venta.
CREATE TABLE DIM_CLIENTE (
    id_cliente          INT             NOT NULL    IDENTITY(1,1),
    cod_sist_origen     VARCHAR(50)     NOT NULL,
    id_cliente_origen   VARCHAR(50)     NOT NULL,
    nombre_cliente      VARCHAR(200)    NOT NULL,
    fecha_nacimiento    DATE            NULL,
    tipo_cliente        VARCHAR(50)     NOT NULL,
    zipcode             VARCHAR(20)     NOT NULL,
    ciudad              VARCHAR(100)    NOT NULL,
    estado              VARCHAR(100)    NOT NULL,
    region              VARCHAR(100)    NOT NULL,
    CONSTRAINT PK_DIM_CLIENTE PRIMARY KEY (id_cliente)
);
GO

-- DIM_RUBRO
CREATE TABLE DIM_RUBRO (
    id_rubro        INT             NOT NULL    IDENTITY(1,1),
    nombre_rubro    VARCHAR(100)    NOT NULL,
    CONSTRAINT PK_DIM_RUBRO PRIMARY KEY (id_rubro)
);
GO

-- DIM_PRESENTACION
CREATE TABLE DIM_PRESENTACION (
    id_presentacion INT             NOT NULL    IDENTITY(1,1),
    volumen         INT   NULL,       -- volumen cm3
	medida			VARCHAR(20)		NULL,	-- cm3
    tipo_envase     VARCHAR(50)     NULL,
	presentacion_original VARCHAR(100) NULL,
    CONSTRAINT PK_DIM_PRESENTACION PRIMARY KEY (id_presentacion)
);
GO

-- DIM_PRODUCTO
CREATE TABLE DIM_PRODUCTO (
    id_producto         INT             NOT NULL    IDENTITY(1,1),
    id_rubro            INT             NOT NULL,
    id_presentacion     INT             NOT NULL,
    cod_sist_origen     VARCHAR(50)     NOT NULL,
    id_producto_origen  VARCHAR(50)     NOT NULL,
    nombre_producto     VARCHAR(200)    NOT NULL,
    es_diet             BIT             NOT NULL DEFAULT 0,
    CONSTRAINT PK_DIM_PRODUCTO PRIMARY KEY (id_producto),
    CONSTRAINT FK_PRODUCTO_RUBRO        FOREIGN KEY (id_rubro)        REFERENCES DIM_RUBRO(id_rubro),
    CONSTRAINT FK_PRODUCTO_PRESENTACION FOREIGN KEY (id_presentacion) REFERENCES DIM_PRESENTACION(id_presentacion)
);
GO

-- DIM_EMPLEADO
CREATE TABLE DIM_EMPLEADO (
    id_empleado         INT             NOT NULL    IDENTITY(1,1),
    cod_sist_origen     VARCHAR(50)     NOT NULL,
	id_empleado_origen VARCHAR(50) NOT NULL,
    nombre_empleado     VARCHAR(200)    NOT NULL,
    genero              VARCHAR(20)     NULL,
    categoria           VARCHAR(100)    NULL,
    fecha_ingreso       DATE            NOT NULL,
    fecha_nacimiento    DATE            NULL,
    nivel_educativo     VARCHAR(100)    NULL,
    antiguedad          INT             NULL,
    CONSTRAINT PK_DIM_EMPLEADO PRIMARY KEY (id_empleado)
);
GO


-- ============================================================
-- TABLAS DE HECHOS
-- ============================================================

-- FCT_VENTAS
CREATE TABLE FCT_VENTAS (
    id_venta            INT             NOT NULL    IDENTITY(1,1),
    fecha_nro           INT             NOT NULL,
    id_cliente          INT             NOT NULL,
    id_producto         INT             NOT NULL,
    id_empleado         INT             NOT NULL,
    region_venta        VARCHAR(50)	    NULL,
    cod_sist_origen     VARCHAR(50)     NOT NULL,
    factura             VARCHAR(50)     NOT NULL,
    cantidad            INT             NOT NULL,
    volumen_total       INT			    NULL,       -- volume cm3
    precio_unitario_usd MONEY           NULL,
    precio_bruto_usd    MONEY           NULL,
    descuento           MONEY           NULL,
    monto_total_usd     MONEY           NULL,
    edad_cliente        INT             NULL,
    edad_empleado       INT             NULL,
    grupo_etario        VARCHAR(10)     NULL,
    antiguedad_empleado INT             NULL,
    CONSTRAINT PK_FCT_VENTAS PRIMARY KEY (id_venta),
    CONSTRAINT FK_VENTAS_FECHA    FOREIGN KEY (fecha_nro)    REFERENCES DIM_FECHA(fecha_nro),
    CONSTRAINT FK_VENTAS_CLIENTE  FOREIGN KEY (id_cliente)   REFERENCES DIM_CLIENTE(id_cliente),
    CONSTRAINT FK_VENTAS_PRODUCTO FOREIGN KEY (id_producto)  REFERENCES DIM_PRODUCTO(id_producto),
    CONSTRAINT FK_VENTAS_EMPLEADO FOREIGN KEY (id_empleado)  REFERENCES DIM_EMPLEADO(id_empleado),
);
GO

-- FCT_STOCK
-- Granularidad: una fila por producto por fecha (periodic snapshot).
-- Sin cod_sist_origen: el stock proviene de una única fuente.
CREATE TABLE FCT_STOCK (
    id_stock		  INT             NOT NULL    IDENTITY(1,1),
    fecha_nro		  INT             NOT NULL,
    id_producto		  INT             NOT NULL,
    unidades_entrada  INT			  NOT NULL,
    CONSTRAINT PK_FCT_STOCK PRIMARY KEY (id_stock),
    CONSTRAINT FK_STOCK_FECHA    FOREIGN KEY (fecha_nro)   REFERENCES DIM_FECHA(fecha_nro),
    CONSTRAINT FK_STOCK_PRODUCTO FOREIGN KEY (id_producto) REFERENCES DIM_PRODUCTO(id_producto),
    CONSTRAINT UQ_STOCK_FECHA_PRODUCTO UNIQUE (fecha_nro, id_producto)
);
GO

USE TDC_DW;
GO

CREATE OR ALTER PROCEDURE SP_LOAD_DIM_FECHA
AS
BEGIN
    DELETE FROM DIM_FECHA;

    -- Registro desconocido
    INSERT INTO DIM_FECHA (fecha_nro, fecha_completa, dia, dia_sem_nro, dia_sem_nomb, mes, mes_nombre, trimestre, semestre, anio, feriado)
    VALUES (-1, NULL, -1, -1, 'Desconocido', -1, 'Desconocido', -1, -1, -1, 0);

    DECLARE @fecha DATE = '2000-01-01';
    DECLARE @fecha_fin DATE = '2009-12-31';

    WHILE @fecha <= @fecha_fin
    BEGIN
        INSERT INTO DIM_FECHA (fecha_nro, fecha_completa, dia, dia_sem_nro, dia_sem_nomb, mes, mes_nombre, trimestre, semestre, anio, feriado)
        VALUES (
            CAST(FORMAT(@fecha, 'yyyyMMdd') AS INT),
            @fecha,
            DAY(@fecha),
            DATEPART(WEEKDAY, @fecha),
            DATENAME(WEEKDAY, @fecha),
            MONTH(@fecha),
            DATENAME(MONTH, @fecha),
            DATEPART(QUARTER, @fecha),
            CASE WHEN MONTH(@fecha) <= 6 THEN 1 ELSE 2 END,
            YEAR(@fecha),
            0
        );
        SET @fecha = DATEADD(DAY, 1, @fecha);
    END;

    UPDATE DIM_FECHA
    SET feriado = 1
    WHERE EXISTS (
        SELECT 1 
        FROM STG_TDC.dbo.STG_HOLIDAYS h
        WHERE DAY(CAST(h.DATE AS DATE)) = DIM_FECHA.dia
        AND MONTH(CAST(h.DATE AS DATE)) = DIM_FECHA.mes
    );
END;
GO

USE TDC_DW;
GO

CREATE OR ALTER PROCEDURE SP_LOAD_DIM_RUBRO
AS
BEGIN
	DELETE FROM DIM_RUBRO;
	DBCC CHECKIDENT ('DIM_RUBRO', RESEED, 0);
		
	INSERT INTO DIM_RUBRO (nombre_rubro)
	SELECT DISTINCT 
		CASE
			WHEN DETAIL LIKE '%Beer%'		THEN 'Beer'
			WHEN DETAIL LIKE '%Cola%'		THEN 'Cola'
			WHEN DETAIL LIKE '%Soda%'		THEN 'Soda'
			WHEN DETAIL LIKE '%Juice%'		THEN 'Juice'
			WHEN DETAIL LIKE '%Energy drink%'		THEN 'Energy drink'
			ELSE 'Desconocido'
		END
	FROM STG_TDC.dbo.STG_PRODUCTS
END;
GO


use TDC_DW;
go

CREATE OR ALTER PROCEDURE SP_LOAD_DIM_PRESENTACION
AS
BEGIN
    DELETE FROM DIM_PRESENTACION;
    DBCC CHECKIDENT ('DIM_PRESENTACION', RESEED, 0);
    INSERT INTO DIM_PRESENTACION (volumen, medida, tipo_envase, presentacion_original)
    SELECT DISTINCT 
        CASE PACKAGE
            WHEN '1 Liter'      THEN 1000
            WHEN '2 Liter'      THEN 2000
            WHEN '330 cm3 can'  THEN 330
            WHEN '500 cm3 can'  THEN 500
            WHEN '670 cm3'      THEN 670
        END AS volumen,
        'cm3' AS medida,
        CASE PACKAGE
            WHEN '330 cm3 can'  THEN 'lata'
            WHEN '500 cm3 can'  THEN 'lata'
            ELSE                     'botella'
        END AS tipo_envase,
        PACKAGE AS presentacion_original
    FROM STG_TDC.dbo.STG_PRODUCTS;
END;
GO

use TDC_DW;
GO

CREATE OR ALTER PROCEDURE SP_LOAD_DIM_PRODUCTO
AS
BEGIN
    DELETE FROM DIM_PRODUCTO;
    DBCC CHECKIDENT ('DIM_PRODUCTO', RESEED, 0);

    INSERT INTO DIM_PRODUCTO (id_rubro, id_presentacion, cod_sist_origen, id_producto_origen, nombre_producto, es_diet)
    SELECT
        r.id_rubro,
        p2.id_presentacion,
        'FLAT_FILE'         AS cod_sist_origen,
        p.PRODUCT_ID        AS id_producto_origen,
        p.DETAIL            AS nombre_producto,
        CASE WHEN p.DETAIL LIKE '%Diet%' THEN 1 ELSE 0 END AS es_diet
    FROM STG_TDC.dbo.STG_PRODUCTS p
    JOIN DIM_RUBRO r ON r.nombre_rubro = 
        CASE 
            WHEN p.DETAIL LIKE '%Beer%'         THEN 'Beer'
            WHEN p.DETAIL LIKE '%Cola%'         THEN 'Cola'
            WHEN p.DETAIL LIKE '%Soda%'         THEN 'Soda'
            WHEN p.DETAIL LIKE '%juice%'        THEN 'Juice'
            WHEN p.DETAIL LIKE '%energy drink%' THEN 'Energy drink'
        END
    JOIN DIM_PRESENTACION p2 ON p2.volumen = 
        CASE p.PACKAGE
            WHEN '1 Liter'     THEN 1000
            WHEN '2 Liter'     THEN 2000
            WHEN '330 cm3 can' THEN 330
            WHEN '500 cm3 can' THEN 500
            WHEN '670 cm3'     THEN 670
        END
        AND p2.tipo_envase =
        CASE p.PACKAGE
            WHEN '330 cm3 can' THEN 'lata'
            WHEN '500 cm3 can' THEN 'lata'
            ELSE 'botella'
        END;
END;
GO


USE TDC_DW;
GO

CREATE OR ALTER PROCEDURE SP_LOAD_DIM_CLIENTE
AS
BEGIN
    -- Limpieza STG_REGIONS
    UPDATE STG_TDC.dbo.STG_REGIONS SET CITY = 'St. Louis' WHERE CITY = 'St. Loius';

    -- Limpieza STG_CUSTOMERS
    UPDATE STG_TDC.dbo.STG_CUSTOMERS SET BIRTH_DATE = NULL  WHERE CUSTOMER_ID = '2036';
    UPDATE STG_TDC.dbo.STG_CUSTOMERS SET BIRTH_DATE = '11/03/1968' WHERE CUSTOMER_ID = '2132';
    UPDATE STG_TDC.dbo.STG_CUSTOMERS SET BIRTH_DATE = '10/05/1964' WHERE CUSTOMER_ID = '2158';
    UPDATE STG_TDC.dbo.STG_CUSTOMERS SET BIRTH_DATE = '11/11/1969' WHERE CUSTOMER_ID = '1018';
    UPDATE STG_TDC.dbo.STG_CUSTOMERS SET BIRTH_DATE = '12/17/1953' WHERE CUSTOMER_ID = '1197';
    UPDATE STG_TDC.dbo.STG_CUSTOMERS SET ZIPCODE = '0' + ZIPCODE WHERE LEN(ZIPCODE) = 4;

    DELETE FROM DIM_CLIENTE;
    DBCC CHECKIDENT ('DIM_CLIENTE', RESEED, 0);

    -- Registro desconocido
    SET IDENTITY_INSERT DIM_CLIENTE ON;
    INSERT INTO DIM_CLIENTE (id_cliente, cod_sist_origen, id_cliente_origen, nombre_cliente, fecha_nacimiento, tipo_cliente, zipcode, ciudad, estado, region)
    VALUES (-1, 'N/A', '-1', 'Desconocido', NULL, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A');
    SET IDENTITY_INSERT DIM_CLIENTE OFF;

    INSERT INTO DIM_CLIENTE (cod_sist_origen, id_cliente_origen, nombre_cliente, fecha_nacimiento, tipo_cliente, zipcode, ciudad, estado, region)
    SELECT
        'XML'                       AS cod_sist_origen,
        c.CUSTOMER_ID               AS id_cliente_origen,
        c.FULL_NAME                 AS nombre_cliente,
        CAST(c.BIRTH_DATE AS DATE)  AS fecha_nacimiento,
        c.TIPO_CLIENTE              AS tipo_cliente,
        c.ZIPCODE                   AS zipcode,
        c.CITY                      AS ciudad,
        c.STATE                     AS estado,
        r.REGION                    AS region
    FROM STG_TDC.dbo.STG_CUSTOMERS c
    JOIN STG_TDC.dbo.STG_REGIONS r ON c.ZIPCODE = r.ZIPCODE;
END;
GO

USE TDC_DW;
GO

CREATE OR ALTER PROCEDURE SP_LOAD_DIM_EMPLEADO
AS
BEGIN
    DELETE FROM DIM_EMPLEADO;
    DBCC CHECKIDENT ('DIM_EMPLEADO', RESEED, 0);

    -- Registro desconocido
    SET IDENTITY_INSERT DIM_EMPLEADO ON;
    INSERT INTO DIM_EMPLEADO (id_empleado, cod_sist_origen, id_empleado_origen, nombre_empleado, genero, categoria, fecha_ingreso, fecha_nacimiento, nivel_educativo, antiguedad)
    VALUES (-1, 'N/A', '-1', 'Desconocido', NULL, NULL, '1900-01-01', NULL, NULL, NULL);
    SET IDENTITY_INSERT DIM_EMPLEADO OFF;

    INSERT INTO DIM_EMPLEADO (cod_sist_origen, id_empleado_origen, nombre_empleado, genero, categoria, fecha_ingreso, fecha_nacimiento, nivel_educativo, antiguedad)
    SELECT
        'EXCEL'                             AS cod_sist_origen,
        EMPLOYEE_ID                         AS id_empleado_origen,
        FULL_NAME                           AS nombre_empleado,
        GENDER                              AS genero,
        CATEGORY                            AS categoria,
        CAST(EMPLOYMENT_DATE AS DATE)       AS fecha_ingreso,
        CAST(BIRTH_DATE AS DATE)            AS fecha_nacimiento,
        EDUCATION_LEVEL                     AS nivel_educativo,
        DATEDIFF(YEAR, CAST(EMPLOYMENT_DATE AS DATE), GETDATE()) AS antiguedad
    FROM STG_TDC.dbo.STG_EMPLOYEES;
END;
GO

USE TDC_DW;
GO

CREATE OR ALTER PROCEDURE SP_LOAD_FCT_VENTAS
AS
BEGIN

    -- ============================================================
    -- PASO 1: LIMPIEZA STAGING
    -- ============================================================
    UPDATE STG_TDC.dbo.STG_BILLING SET REGION = 'Central' WHERE REGION = 'North';
    UPDATE STG_TDC.dbo.STG_BILLING_DETAIL SET PRODUCT_ID = '0' + PRODUCT_ID WHERE LEN(PRODUCT_ID) = 1;
    UPDATE STG_TDC.dbo.STG_PRICES SET PRICE = CAST(ROUND(CAST(PRICE AS FLOAT), 2) AS VARCHAR(50));
    UPDATE STG_TDC.dbo.STG_HISTORY_SALES SET PRODUCT_ID = '0' + PRODUCT_ID WHERE LEN(PRODUCT_ID) = 1;

    DELETE FROM TDC_DW.dbo.FCT_VENTAS;
    DBCC CHECKIDENT ('TDC_DW.dbo.FCT_VENTAS', RESEED, 0);

    -- ============================================================
    -- PASO 2: PRECIOS VIGENTES (HISTORY SALES)
    -- ============================================================
    IF OBJECT_ID('tempdb..#precios') IS NOT NULL DROP TABLE #precios;

    SELECT 
        h.ID,
        h.PRODUCT_ID,
        h.DATE,
        COALESCE(
            (SELECT TOP 1 CAST(p.PRICE AS MONEY)
             FROM STG_TDC.dbo.STG_PRICES p
             WHERE p.PRODUCT_ID = h.PRODUCT_ID
             AND CAST(p.DATE AS DATE) <= CAST(h.DATE AS DATE)
             ORDER BY CAST(p.DATE AS DATE) DESC),
            (SELECT TOP 1 CAST(p.PRICE AS MONEY)
             FROM STG_TDC.dbo.STG_PRICES p
             WHERE p.PRODUCT_ID = h.PRODUCT_ID
             ORDER BY CAST(p.DATE AS DATE) ASC)
        ) AS precio_unitario
    INTO #precios
    FROM STG_TDC.dbo.STG_HISTORY_SALES h;

    -- ============================================================
    -- PASO 3: MONTOS TOTALES POR FACTURA (HISTORY SALES)
    -- ============================================================
    IF OBJECT_ID('tempdb..#montos_factura') IS NOT NULL DROP TABLE #montos_factura;

    SELECT 
        h.BILLING_ID,
        SUM(CAST(h.QUANTITY AS INT) * pr.precio_unitario) AS monto_total_factura
    INTO #montos_factura
    FROM STG_TDC.dbo.STG_HISTORY_SALES h
    JOIN #precios pr ON pr.ID = h.ID
    GROUP BY h.BILLING_ID;

    -- ============================================================
    -- PASO 4: DESCUENTOS (HISTORY SALES)
    -- ============================================================
    IF OBJECT_ID('tempdb..#descuentos') IS NOT NULL DROP TABLE #descuentos;

    SELECT 
        mf.BILLING_ID,
        MAX(CAST(d.PERCENTAGE AS DECIMAL(5,2))) AS porcentaje_descuento
    INTO #descuentos
    FROM #montos_factura mf
    JOIN STG_TDC.dbo.STG_HISTORY_SALES h ON h.BILLING_ID = mf.BILLING_ID
    JOIN STG_TDC.dbo.STG_DISCOUNTS d 
        ON mf.monto_total_factura >= CAST(d.TOTAL_BILLING AS MONEY)
        AND CAST(h.DATE AS DATE) >= CAST(d.FROM_DATE AS DATE)
        AND (d.UNTIL_DATE IS NULL OR CAST(h.DATE AS DATE) <= CAST(d.UNTIL_DATE AS DATE))
    GROUP BY mf.BILLING_ID;

    -- ============================================================
    -- PASO 5: INSERT FCT_VENTAS - VENTAS HISTORICAS
    -- ============================================================
    INSERT INTO TDC_DW.dbo.FCT_VENTAS (fecha_nro, id_cliente, id_producto, id_empleado, region_venta, cod_sist_origen, factura, cantidad, volumen_total, precio_unitario_usd, precio_bruto_usd, descuento, monto_total_usd, edad_cliente, edad_empleado, grupo_etario, antiguedad_empleado)
    SELECT
        ISNULL(CAST(FORMAT(CAST(h.DATE AS DATE), 'yyyyMMdd') AS INT), -1),
        ISNULL(dc.id_cliente, -1),
        dp.id_producto,
        ISNULL(de.id_empleado, -1),
        h.REGION,
        'SQL_SERVER',
        h.BILLING_ID,
        CAST(h.QUANTITY AS INT),
        CAST(h.QUANTITY AS INT) * dp2.volumen,
        pr.precio_unitario,
        CAST(h.QUANTITY AS INT) * pr.precio_unitario,
        CAST(h.QUANTITY AS INT) * pr.precio_unitario * ISNULL(d.porcentaje_descuento, 0) / 100,
        CAST(h.QUANTITY AS INT) * pr.precio_unitario - CAST(h.QUANTITY AS INT) * pr.precio_unitario * ISNULL(d.porcentaje_descuento, 0) / 100,
        DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(h.DATE AS DATE)),
        DATEDIFF(YEAR, de.fecha_nacimiento, CAST(h.DATE AS DATE)),
		CASE
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(h.DATE AS DATE)) BETWEEN 0  AND 12 THEN '0-12'
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(h.DATE AS DATE)) BETWEEN 13 AND 19 THEN '13-19'
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(h.DATE AS DATE)) BETWEEN 20 AND 39 THEN '20-39'
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(h.DATE AS DATE)) BETWEEN 40 AND 50 THEN '40-50'
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(h.DATE AS DATE)) BETWEEN 51 AND 65 THEN '51-65'
			ELSE '66+'
		END,
        DATEDIFF(YEAR, de.fecha_ingreso, CAST(h.DATE AS DATE))
    FROM STG_TDC.dbo.STG_HISTORY_SALES h
    JOIN #precios pr ON pr.ID = h.ID
    LEFT JOIN #descuentos d ON d.BILLING_ID = h.BILLING_ID
    LEFT JOIN TDC_DW.dbo.DIM_CLIENTE dc ON dc.id_cliente_origen = h.CUSTOMER_ID AND dc.id_cliente <> -1
    LEFT JOIN TDC_DW.dbo.DIM_EMPLEADO de ON de.id_empleado_origen = h.EMPLOYEE_ID AND de.id_empleado <> -1
    JOIN TDC_DW.dbo.DIM_PRODUCTO dp ON dp.id_producto_origen = h.PRODUCT_ID
    JOIN TDC_DW.dbo.DIM_PRESENTACION dp2 ON dp2.id_presentacion = dp.id_presentacion;


-- ============================================================
   -- PASO 6: PRECIOS VIGENTES (BILLING)
-- ============================================================

    IF OBJECT_ID('tempdb..#precios_billing') IS NOT NULL DROP TABLE #precios_billing;

    SELECT 
        bd.BILLING_ID,
        bd.PRODUCT_ID,
        b.DATE,
        CAST(bd.QUANTITY AS INT) AS cantidad,
        COALESCE(
            (SELECT TOP 1 CAST(p.PRICE AS MONEY)
             FROM STG_TDC.dbo.STG_PRICES p
             WHERE p.PRODUCT_ID = bd.PRODUCT_ID
             AND CAST(p.DATE AS DATE) <= CAST(b.DATE AS DATE)
             ORDER BY CAST(p.DATE AS DATE) DESC),
            (SELECT TOP 1 CAST(p.PRICE AS MONEY)
             FROM STG_TDC.dbo.STG_PRICES p
             WHERE p.PRODUCT_ID = bd.PRODUCT_ID
             ORDER BY CAST(p.DATE AS DATE) ASC)
        ) AS precio_unitario
    INTO #precios_billing
    FROM STG_TDC.dbo.STG_BILLING_DETAIL bd
    LEFT JOIN STG_TDC.dbo.STG_BILLING b ON bd.BILLING_ID = b.BILLING_ID;


-- ============================================================
    -- PASO 7: MONTOS TOTALES POR FACTURA (BILLING)
    -- ============================================================
    IF OBJECT_ID('tempdb..#montos_factura_billing') IS NOT NULL DROP TABLE #montos_factura_billing;

    SELECT 
        pb.BILLING_ID,
        SUM(pb.cantidad * pb.precio_unitario) AS monto_total_factura
    INTO #montos_factura_billing
    FROM #precios_billing pb
    GROUP BY pb.BILLING_ID;


-- ============================================================
    -- PASO 8: DESCUENTOS (BILLING)
-- ============================================================

    IF OBJECT_ID('tempdb..#descuentos_billing') IS NOT NULL DROP TABLE #descuentos_billing;

    SELECT 
        mfb.BILLING_ID,
        MAX(CAST(d.PERCENTAGE AS DECIMAL(5,2))) AS porcentaje_descuento
    INTO #descuentos_billing
    FROM #montos_factura_billing mfb
    LEFT JOIN STG_TDC.dbo.STG_BILLING b ON b.BILLING_ID = mfb.BILLING_ID
    JOIN STG_TDC.dbo.STG_DISCOUNTS d 
        ON mfb.monto_total_factura >= CAST(d.TOTAL_BILLING AS MONEY)
        AND CAST(b.DATE AS DATE) >= CAST(d.FROM_DATE AS DATE)
        AND (d.UNTIL_DATE IS NULL OR CAST(b.DATE AS DATE) <= CAST(d.UNTIL_DATE AS DATE))
    GROUP BY mfb.BILLING_ID;


-- ============================================================
    -- PASO 9: INSERT FCT_VENTAS - VENTAS ACTUALES (MYSQL)
    -- ============================================================
    INSERT INTO TDC_DW.dbo.FCT_VENTAS (fecha_nro, id_cliente, id_producto, id_empleado, region_venta, cod_sist_origen, factura, cantidad, volumen_total, precio_unitario_usd, precio_bruto_usd, descuento, monto_total_usd, edad_cliente, edad_empleado, grupo_etario, antiguedad_empleado)
    SELECT
        ISNULL(CAST(FORMAT(CAST(b.DATE AS DATE), 'yyyyMMdd') AS INT), -1),
        ISNULL(dc.id_cliente, -1),
        dp.id_producto,
        ISNULL(de.id_empleado, -1),
        b.REGION,
        'MYSQL',
        bd.BILLING_ID,
        pb.cantidad,
        pb.cantidad * dp2.volumen,
        pb.precio_unitario,
        pb.cantidad * pb.precio_unitario,
        pb.cantidad * pb.precio_unitario * ISNULL(db_.porcentaje_descuento, 0) / 100,
        pb.cantidad * pb.precio_unitario - pb.cantidad * pb.precio_unitario * ISNULL(db_.porcentaje_descuento, 0) / 100,
        DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(b.DATE AS DATE)),
        DATEDIFF(YEAR, de.fecha_nacimiento, CAST(b.DATE AS DATE)),
		CASE
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(b.DATE AS DATE)) BETWEEN 0  AND 12 THEN '0-12'
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(b.DATE AS DATE)) BETWEEN 13 AND 19 THEN '13-19'
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(b.DATE AS DATE)) BETWEEN 20 AND 39 THEN '20-39'
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(b.DATE AS DATE)) BETWEEN 40 AND 50 THEN '40-50'
			WHEN DATEDIFF(YEAR, dc.fecha_nacimiento, CAST(b.DATE AS DATE)) BETWEEN 51 AND 65 THEN '51-65'
			ELSE '66+'
		END,
        DATEDIFF(YEAR, de.fecha_ingreso, CAST(b.DATE AS DATE))
    FROM STG_TDC.dbo.STG_BILLING_DETAIL bd
    JOIN #precios_billing pb ON pb.BILLING_ID = bd.BILLING_ID AND pb.PRODUCT_ID = bd.PRODUCT_ID
    LEFT JOIN STG_TDC.dbo.STG_BILLING b ON bd.BILLING_ID = b.BILLING_ID
    LEFT JOIN #descuentos_billing db_ ON db_.BILLING_ID = bd.BILLING_ID
    LEFT JOIN TDC_DW.dbo.DIM_CLIENTE dc ON dc.id_cliente_origen = b.CUSTOMER_ID AND dc.id_cliente <> -1
    LEFT JOIN TDC_DW.dbo.DIM_EMPLEADO de ON de.id_empleado_origen = b.EMPLOYEE_ID AND de.id_empleado <> -1
    JOIN TDC_DW.dbo.DIM_PRODUCTO dp ON dp.id_producto_origen = bd.PRODUCT_ID
    JOIN TDC_DW.dbo.DIM_PRESENTACION dp2 ON dp2.id_presentacion = dp.id_presentacion;

END;
GO


CREATE OR ALTER PROCEDURE SP_LOAD_FCT_STOCK
AS
BEGIN
    SET NOCOUNT ON;

    -- ============================================================
    -- PASO 1: LIMPIEZA STAGING - normalizar formato de fecha
    -- ============================================================
    UPDATE STG_TDC.dbo.STG_STOCK
    SET DATE = REPLACE(REPLACE(DATE, 'a.m.', 'AM'), 'p.m.', 'PM')
    WHERE DATE LIKE '%a.m.%' OR DATE LIKE '%p.m.%';

    -- ============================================================
    -- PASO 2: VACIAR FCT_STOCK
    -- ============================================================
    DELETE FROM TDC_DW.dbo.FCT_STOCK;
    DBCC CHECKIDENT ('TDC_DW.dbo.FCT_STOCK', RESEED, 0);

    -- ============================================================
    -- PASO 3: INSERTAR MOVIMIENTOS AGRUPADOS POR DIA Y PRODUCTO
    -- ============================================================
    INSERT INTO TDC_DW.dbo.FCT_STOCK (fecha_nro, id_producto, unidades_entrada)
    SELECT
        ISNULL(df.fecha_nro, -1)                                    AS fecha_nro,
        dp.id_producto,
        SUM(CAST(s.VARIATION AS INT))                               AS unidades_entrada
    FROM STG_TDC.dbo.STG_STOCK s
    INNER JOIN TDC_DW.dbo.DIM_PRODUCTO dp 
        ON s.PRODUCT_ID = dp.id_producto_origen
    LEFT JOIN TDC_DW.dbo.DIM_FECHA df 
        ON df.fecha_nro = CAST(FORMAT(CONVERT(DATE, LEFT(s.DATE, 10), 101), 'yyyyMMdd') AS INT)
    GROUP BY
        ISNULL(df.fecha_nro, -1),
        dp.id_producto;

END;
GO