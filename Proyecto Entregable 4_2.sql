---------- a) Base de datos del proyecto ----------
IF DB_ID('EmpresaAliadaDW') IS NULL
    CREATE DATABASE EmpresaAliadaDW;
GO
USE EmpresaAliadaDW;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='dim')  EXEC('CREATE SCHEMA dim');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='fact') EXEC('CREATE SCHEMA fact');
GO


---------- b) Estructura de tablas ----------
/* 1) DIM_CATEGORY */
IF OBJECT_ID('dim.DIM_CATEGORY') IS NULL
CREATE TABLE dim.DIM_CATEGORY(
    CategoryKey     INT IDENTITY(1,1) PRIMARY KEY,
    CategoryID      INT           NOT NULL,
    CategoryName    NVARCHAR(150) NOT NULL,
    IsActive        BIT           NOT NULL DEFAULT(1),
    LoadDateUtc     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_DIM_CATEGORY_Business UNIQUE (CategoryID)
);
GO

/* 2) DIM_SEGMENT  (p.ej.: Consumer / Corporate … y opcionalmente Región) */
IF OBJECT_ID('dim.DIM_SEGMENT') IS NULL
CREATE TABLE dim.DIM_SEGMENT(
    SegmentKey      INT IDENTITY(1,1) PRIMARY KEY,
    CategoryID      INT            NOT NULL,
    Attr1           NVARCHAR(100)  NULL,
    Attr2           NVARCHAR(100)  NULL,
    Attr3           NVARCHAR(100)  NULL,
    [Format]        NVARCHAR(50)   NULL,
    SegmentName     NVARCHAR(150)  NOT NULL,
    IsActive        BIT            NOT NULL DEFAULT(1),
    LoadDateUtc     DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Segment_CategoryID 
        FOREIGN KEY (CategoryID) REFERENCES dim.DIM_CATEGORY(CategoryID),
    -- Evitar duplicados del mismo “cubo” de atributos:
    CONSTRAINT UQ_DIM_SEGMENT_Grain UNIQUE (CategoryID, Attr1, Attr2, Attr3, [Format])
);
GO


/* 3) DIM_PRODUCT */
IF OBJECT_ID('dim.DIM_PRODUCT') IS NULL
CREATE TABLE dim.DIM_PRODUCT(
    ProductKey      INT IDENTITY(1,1) PRIMARY KEY,
    ItemCode        NVARCHAR(50)   NOT NULL,
    ItemDescription NVARCHAR(250)  NOT NULL,
    Manufacturer    NVARCHAR(120)  NULL,
    Brand           NVARCHAR(120)  NULL,
    CategoryID      INT            NOT NULL,
    [Format]        NVARCHAR(50)   NULL,
    Attr1           NVARCHAR(100)  NULL,
    Attr2           NVARCHAR(100)  NULL,
    Attr3           NVARCHAR(100)  NULL,

    IsActive        BIT            NOT NULL DEFAULT(1),
    LoadDateUtc     DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_DIM_PRODUCT_Item UNIQUE (ItemCode),
    CONSTRAINT FK_Product_CategoryID 
        FOREIGN KEY (CategoryID) REFERENCES dim.DIM_CATEGORY(CategoryID)
);
GO



IF OBJECT_ID('fact.FACT_SALES') IS NOT NULL
BEGIN
    DROP TABLE fact.FACT_SALES;
END
IF OBJECT_ID('dim.DIM_CALENDAR') IS NOT NULL
BEGIN
    DROP TABLE dim.DIM_CALENDAR;
END
GO


/* 4) DIM_CALENDAR (clave YYYYMMDD) */
CREATE TABLE dim.DIM_CALENDAR(
    DateKey      INT          NOT NULL PRIMARY KEY,
    FullDate     DATE         NOT NULL,
    WeekCode     NVARCHAR(10) NOT NULL,
    [Year]       SMALLINT     NOT NULL,
    [Month]      TINYINT      NOT NULL,
    WeekNumber   TINYINT      NOT NULL,
    MonthName    NVARCHAR(20) NULL,
    DayOfWeek    TINYINT      NULL,
    LoadDateUtc  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_DIM_CALENDAR_Week UNIQUE (WeekCode)
);
GO


/* 5) FACT_SALES */
CREATE TABLE fact.FACT_SALES(
    SalesKey                 BIGINT IDENTITY(1,1) PRIMARY KEY,
    ProductKey               INT           NOT NULL,
    WeekCode                 NVARCHAR(10)  NOT NULL,
    Region                   NVARCHAR(120) NOT NULL,
    TotalUnitSales           DECIMAL(18,4) NULL,
    TotalValueSales          DECIMAL(18,4) NULL,
    TotalUnitAvgWeeklySales  DECIMAL(18,4) NULL,
    LoadDateUtc              DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_FACT_Product FOREIGN KEY (ProductKey) REFERENCES dim.DIM_PRODUCT(ProductKey),
    CONSTRAINT FK_FACT_Week    FOREIGN KEY (WeekCode)   REFERENCES dim.DIM_CALENDAR(WeekCode)
);
GO

CREATE INDEX IX_FACT_SALES_Week    ON fact.FACT_SALES(WeekCode);
CREATE INDEX IX_FACT_SALES_Product ON fact.FACT_SALES(ProductKey);
CREATE INDEX IX_FACT_SALES_Region  ON fact.FACT_SALES(Region);





---------- c) Importación + Carga ----------
USE EmpresaAliadaDW;
SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='stg') EXEC('CREATE SCHEMA stg');

IF OBJECT_ID('stg.DIM_CATEGORY') IS NOT NULL DROP TABLE stg.DIM_CATEGORY;
IF OBJECT_ID('stg.DIM_PRODUCT')  IS NOT NULL DROP TABLE stg.DIM_PRODUCT;
IF OBJECT_ID('stg.DIM_SEGMENT')  IS NOT NULL DROP TABLE stg.DIM_SEGMENT;
IF OBJECT_ID('stg.DIM_CALENDAR') IS NOT NULL DROP TABLE stg.DIM_CALENDAR;
IF OBJECT_ID('stg.FACT_SALES')   IS NOT NULL DROP TABLE stg.FACT_SALES;

-- 1) Tablas STAGING (tipos flexibles)
CREATE TABLE stg.DIM_CATEGORY(
    ID_CATEGORY  NVARCHAR(50)  NULL,
    CATEGORY     NVARCHAR(200) NULL
);

CREATE TABLE stg.DIM_PRODUCT(
    MANUFACTURER     NVARCHAR(200) NULL,
    BRAND            NVARCHAR(200) NULL,
    ITEM             NVARCHAR(100) NULL,
    ITEM_DESCRIPTION NVARCHAR(300) NULL,
    CATEGORY         NVARCHAR(50)  NULL,
    FORMAT           NVARCHAR(100) NULL,
    ATTR1            NVARCHAR(100) NULL,
    ATTR2            NVARCHAR(100) NULL,
    ATTR3            NVARCHAR(100) NULL
);

CREATE TABLE stg.DIM_SEGMENT(
    CATEGORY NVARCHAR(50)  NULL,
    ATTR1    NVARCHAR(100) NULL,
    ATTR2    NVARCHAR(100) NULL,
    ATTR3    NVARCHAR(100) NULL,
    FORMAT   NVARCHAR(100) NULL,
    SEGMENT  NVARCHAR(150) NULL
);

CREATE TABLE stg.DIM_CALENDAR(
    [WEEK]        NVARCHAR(20) NULL,
    [YEAR]        NVARCHAR(10) NULL,
    [MONTH]       NVARCHAR(10) NULL,
    [WEEK_NUMBER] NVARCHAR(10) NULL,
    [DATE]        NVARCHAR(50) NULL
);


CREATE TABLE stg.FACT_SALES(
    [WEEK]                        NVARCHAR(20)  NULL,
    [ITEM_CODE]                   NVARCHAR(100) NULL,
    [TOTAL_UNIT_SALES]            NVARCHAR(100) NULL,
    [TOTAL_VALUE_SALES]           NVARCHAR(100) NULL,
    [TOTAL_UNIT_AVG_WEEKLY_SALES] NVARCHAR(100) NULL,
    [REGION]                      NVARCHAR(200) NULL
);


-- 2) CSV
-- DIM_CATEGORY.csv
BULK INSERT stg.DIM_CATEGORY
FROM 'C:\Data\EmpresaAliada\DIM_CATEGORY.csv'
WITH (FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0d0a', CODEPAGE='65001', FIELDQUOTE='"', TABLOCK);

-- FACT_SALES.csv
BULK INSERT stg.FACT_SALES
FROM 'C:\Data\EmpresaAliada\FACT_SALES.csv'
WITH (FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0d0a', CODEPAGE='65001', FIELDQUOTE='"', TABLOCK);

-- DIM_PRODUCT.csv
BULK INSERT stg.DIM_PRODUCT
FROM 'C:\Data\EmpresaAliada\Copia de DIM_PRODUCT.csv'
WITH (FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0d0a', CODEPAGE='65001', FIELDQUOTE='"', TABLOCK);

-- DIM_SEGMENT.csv
BULK INSERT stg.DIM_SEGMENT
FROM 'C:\Data\EmpresaAliada\Copia de DIM_SEGMENT.csv'
WITH (FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0d0a', CODEPAGE='65001', FIELDQUOTE='"', TABLOCK);

-- DIM_CALENDAR.csv
BULK INSERT stg.DIM_CALENDAR
FROM 'C:\Data\EmpresaAliada\Copia de DIM_CALENDAR.csv'
WITH (FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0d0a', CODEPAGE='65001', FIELDQUOTE='"', TABLOCK);

/* 3) CARGA a DIMENSIONES */
-- DIM_CATEGORY
;WITH C AS (
    SELECT DISTINCT
        CategoryID   = TRY_CONVERT(INT, LTRIM(RTRIM(ID_CATEGORY))),
        CategoryName = LTRIM(RTRIM(CATEGORY))
    FROM stg.DIM_CATEGORY
)
INSERT INTO dim.DIM_CATEGORY (CategoryID, CategoryName)
SELECT C.CategoryID, C.CategoryName
FROM C
WHERE C.CategoryID IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM dim.DIM_CATEGORY D
        WHERE D.CategoryID = C.CategoryID
  );

-- DIM_SEGMENT
;WITH S AS (
    SELECT
        CategoryID = TRY_CONVERT(INT, LTRIM(RTRIM(S.CATEGORY))),
        Attr1      = NULLIF(LTRIM(RTRIM(S.ATTR1)),  N''),
        Attr2      = NULLIF(LTRIM(RTRIM(S.ATTR2)),  N''),
        Attr3      = NULLIF(LTRIM(RTRIM(S.ATTR3)),  N''),
        [Format]   = NULLIF(LTRIM(RTRIM(S.FORMAT)), N''),
        Segment    = LTRIM(RTRIM(S.SEGMENT))
    FROM stg.DIM_SEGMENT S
),

G AS (
    SELECT
        CategoryID, Attr1, Attr2, Attr3, [Format],
        SegmentName = MIN(Segment)
    FROM S
    WHERE CategoryID IS NOT NULL
    GROUP BY CategoryID, Attr1, Attr2, Attr3, [Format]
)
INSERT INTO dim.DIM_SEGMENT (CategoryID, Attr1, Attr2, Attr3, [Format], SegmentName)
SELECT g.CategoryID, g.Attr1, g.Attr2, g.Attr3, g.[Format], g.SegmentName
FROM G g
WHERE NOT EXISTS (
    SELECT 1
    FROM dim.DIM_SEGMENT d
    WHERE d.CategoryID        = g.CategoryID
      AND ISNULL(d.Attr1,'')  = ISNULL(g.Attr1,'')
      AND ISNULL(d.Attr2,'')  = ISNULL(g.Attr2,'')
      AND ISNULL(d.Attr3,'')  = ISNULL(g.Attr3,'')
      AND ISNULL(d.[Format],'') = ISNULL(g.[Format],'')
);



  -- DIM_PRODUCT
;WITH P0 AS (
    SELECT DISTINCT
        ItemCode       = NULLIF(LTRIM(RTRIM(ITEM)), N''),
        ItemDescription= LTRIM(RTRIM(ITEM_DESCRIPTION)),
        Manufacturer   = NULLIF(LTRIM(RTRIM(MANUFACTURER)), N''),
        Brand          = NULLIF(LTRIM(RTRIM(BRAND)),        N''),
        CategoryID     = TRY_CONVERT(INT, LTRIM(RTRIM(CATEGORY))),
        [Format]       = NULLIF(LTRIM(RTRIM([FORMAT])),     N''),
        Attr1          = NULLIF(LTRIM(RTRIM(ATTR1)),        N''),
        Attr2          = NULLIF(LTRIM(RTRIM(ATTR2)),        N''),
        Attr3          = NULLIF(LTRIM(RTRIM(ATTR3)),        N'')
    FROM stg.DIM_PRODUCT
),
P1 AS (   -- descarta códigos inválidos
    SELECT *
    FROM P0
    WHERE ItemCode IS NOT NULL
      AND UPPER(ItemCode) NOT IN (N'N/A', N'NA', N'NO DEFINIDO')
      AND CategoryID IS NOT NULL
),
P2 AS (   -- una fila por ItemCode
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY ItemCode ORDER BY ItemDescription) AS rn
    FROM P1
)
INSERT INTO dim.DIM_PRODUCT
    (ItemCode, ItemDescription, Manufacturer, Brand, CategoryID, [Format], Attr1, Attr2, Attr3)
SELECT
    p.ItemCode, p.ItemDescription, p.Manufacturer, p.Brand, p.CategoryID, p.[Format], p.Attr1, p.Attr2, p.Attr3
FROM P2 p
LEFT JOIN dim.DIM_PRODUCT d
       ON d.ItemCode = p.ItemCode
WHERE p.rn = 1
  AND d.ProductKey IS NULL;

-- DIM_CALENDAR
DELETE d
FROM dim.DIM_CALENDAR d
JOIN (SELECT DISTINCT REPLACE(REPLACE(REPLACE(LTRIM(RTRIM([WEEK])),'"',''), CHAR(9), ''), CHAR(160), '') AS WeekClean
      FROM stg.DIM_CALENDAR) s
  ON s.WeekClean = d.WeekCode;


UPDATE s
SET [WEEK] = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM([WEEK])),'"',''), CHAR(9), ''), CHAR(160), '')
FROM stg.FACT_SALES s;

;WITH X AS (
    SELECT
        WeekClean  = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM([WEEK])),'"',''), CHAR(9), ''), CHAR(160), ''),
        [Year]     = TRY_CONVERT(SMALLINT, [YEAR]),
        [Month]    = TRY_CONVERT(TINYINT,  [MONTH]),
        WeekNumber = TRY_CONVERT(TINYINT,  [WEEK_NUMBER]),
        FullDate   = CASE
                       WHEN TRY_CONVERT(FLOAT, [DATE]) IS NOT NULL
                         THEN DATEADD(DAY,
                                      CONVERT(INT, FLOOR(CONVERT(FLOAT, [DATE]))),
                                      DATEFROMPARTS(1899,12,30))
                       ELSE COALESCE(
                              TRY_CONVERT(date, [DATE], 103),
                              TRY_CONVERT(date, [DATE], 101),
                              TRY_CONVERT(date, [DATE])
                            )
                     END
    FROM stg.DIM_CALENDAR
),
R AS (
    SELECT
        DateKey    = TRY_CONVERT(INT, FORMAT(FullDate,'yyyyMMdd')),
        FullDate,
        WeekCode   = WeekClean,
        [Year], [Month], WeekNumber
    FROM X
    WHERE FullDate IS NOT NULL
      AND WeekClean IS NOT NULL AND WeekClean <> N''
),
G AS (   -- dedup por DateKey
    SELECT
        DateKey,
        FullDate   = MIN(FullDate),
        WeekCode   = MIN(WeekCode),
        [Year]     = MIN([Year]),
        [Month]    = MIN([Month]),
        WeekNumber = MIN(WeekNumber)
    FROM R
    GROUP BY DateKey
)
INSERT INTO dim.DIM_CALENDAR
    (DateKey, FullDate, WeekCode, [Year], [Month], WeekNumber, MonthName, DayOfWeek)
SELECT
    g.DateKey, g.FullDate, g.WeekCode, g.[Year], g.[Month], g.WeekNumber,
    DATENAME(MONTH, g.FullDate), DATEPART(WEEKDAY, g.FullDate)
FROM G g
WHERE NOT EXISTS (SELECT 1 FROM dim.DIM_CALENDAR d WHERE d.DateKey = g.DateKey);





  /* 4) CARGA a FACT */
TRUNCATE TABLE fact.FACT_SALES;
GO

;WITH P AS (   -- ItemDigits desde DIM_PRODUCT
    SELECT
        d.ProductKey,
        ItemDigits =
        (
          SELECT '' + SUBSTRING(d.ItemCode, v.number, 1)
          FROM master..spt_values v
          WHERE v.type = 'P'
            AND v.number BETWEEN 1 AND LEN(d.ItemCode)
            AND SUBSTRING(d.ItemCode, v.number, 1) LIKE '[0-9]'
          ORDER BY v.number
          FOR XML PATH(''), TYPE
        ).value('.','nvarchar(100)')
    FROM dim.DIM_PRODUCT d
    WHERE d.ItemCode IS NOT NULL
),
F0 AS (  -- limpia WEEK / ITEM_CODE / REGION y prepara textos numéricos
    SELECT
        WeekClean = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(s.[WEEK])),'"',''), CHAR(9), ''), CHAR(160), ''),
        ItemClean = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(s.[ITEM_CODE])),'"',''), CHAR(9), ''), CHAR(160), ''),
        Region    = LTRIM(RTRIM(s.[REGION])),

        Raw_TUS   = s.[TOTAL_UNIT_SALES],
        Raw_TVS   = s.[TOTAL_VALUE_SALES],
        Raw_TUAW  = s.[TOTAL_UNIT_AVG_WEEKLY_SALES]
    FROM stg.FACT_SALES s
),
F0C AS ( -- quita comillas/espacios, coma->punto
    SELECT
        WeekClean, ItemClean, Region,
        Clean_TUS  = NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Raw_TUS ,'"',''),' ',''),CHAR(160),''),',','.'),''),
        Clean_TVS  = NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Raw_TVS ,'"',''),' ',''),CHAR(160),''),',','.'),''),
        Clean_TUAW = NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Raw_TUAW,'"',''),' ',''),CHAR(160),''),',','.'),'')
    FROM F0
),
F1 AS (  -- convierte a DECIMAL y extrae dígitos de Item
    SELECT
        WeekClean,
        Region,
        TotalUnitSales          = TRY_CONVERT(DECIMAL(18,4), Clean_TUS),
        TotalValueSales         = TRY_CONVERT(DECIMAL(18,4), Clean_TVS),
        TotalUnitAvgWeeklySales = TRY_CONVERT(DECIMAL(18,4), Clean_TUAW),
        ItemDigits =
        (
          SELECT '' + SUBSTRING(f.ItemClean, v.number, 1)
          FROM master..spt_values v
          WHERE v.type = 'P'
            AND v.number BETWEEN 1 AND LEN(f.ItemClean)
            AND SUBSTRING(f.ItemClean, v.number, 1) LIKE '[0-9]'
          ORDER BY v.number
          FOR XML PATH(''), TYPE
        ).value('.','nvarchar(100)')
    FROM F0C f
    WHERE f.ItemClean IS NOT NULL
      AND f.WeekClean IS NOT NULL
      AND f.Region   IS NOT NULL
),
F2 AS (  -- resuelve surrogate keys
    SELECT
        p.ProductKey,
        c.WeekCode,
        f.Region,
        f.TotalUnitSales,
        f.TotalValueSales,
        f.TotalUnitAvgWeeklySales
    FROM F1 f
    INNER JOIN P                p ON p.ItemDigits = f.ItemDigits
    INNER JOIN dim.DIM_CALENDAR c ON c.WeekCode  = f.WeekClean
)
INSERT INTO fact.FACT_SALES
    (ProductKey, WeekCode, Region, TotalUnitSales, TotalValueSales, TotalUnitAvgWeeklySales)
SELECT
    t.ProductKey, t.WeekCode, t.Region,
    t.TotalUnitSales, t.TotalValueSales, t.TotalUnitAvgWeeklySales
FROM F2 t;

---------- d) Validaciones Ràpidas ----------
SET NOCOUNT ON;

-- Conteos por tabla
SELECT 'DIM_CATEGORY'  AS Tabla, COUNT(*) AS Regs FROM dim.DIM_CATEGORY
UNION ALL SELECT 'DIM_PRODUCT',  COUNT(*) FROM dim.DIM_PRODUCT
UNION ALL SELECT 'DIM_SEGMENT',  COUNT(*) FROM dim.DIM_SEGMENT
UNION ALL SELECT 'DIM_CALENDAR', COUNT(*) FROM dim.DIM_CALENDAR
UNION ALL SELECT 'FACT_SALES',   COUNT(*) FROM fact.FACT_SALES;

-- Muestras de cada tabla (para screenshots)
SELECT TOP (10) * FROM dim.DIM_CATEGORY ORDER BY CategoryID;
SELECT TOP (10) * FROM dim.DIM_PRODUCT  ORDER BY ProductKey;
SELECT TOP (10) * FROM dim.DIM_SEGMENT  ORDER BY SegmentKey;
SELECT TOP (10) * FROM dim.DIM_CALENDAR ORDER BY FullDate;
SELECT TOP (10) * FROM fact.FACT_SALES  ORDER BY SalesKey;

-- Integridad referencial efectiva (huérfanos = 0)
SELECT 
    SUM(CASE WHEN p.ProductKey IS NULL THEN 1 ELSE 0 END) AS Orphans_Product,
    SUM(CASE WHEN c.WeekCode    IS NULL THEN 1 ELSE 0 END) AS Orphans_WeekCode
FROM fact.FACT_SALES f
LEFT JOIN dim.DIM_PRODUCT  p ON p.ProductKey = f.ProductKey
LEFT JOIN dim.DIM_CALENDAR c ON c.WeekCode   = f.WeekCode;

-- Nulidades en medidas (deben ser 0)
SELECT 
    SUM(CASE WHEN TotalUnitSales         IS NULL THEN 1 ELSE 0 END) AS Null_TUS,
    SUM(CASE WHEN TotalValueSales        IS NULL THEN 1 ELSE 0 END) AS Null_TVS,
    SUM(CASE WHEN TotalUnitAvgWeeklySales IS NULL THEN 1 ELSE 0 END) AS Null_TUAW
FROM fact.FACT_SALES;

-- Duplicados de grano en FACT (ProductKey, WeekCode, Region)
SELECT TOP (10) ProductKey, WeekCode, Region, COUNT(*) AS DupRows
FROM fact.FACT_SALES
GROUP BY ProductKey, WeekCode, Region
HAVING COUNT(*) > 1;

SELECT COUNT(*) AS TotalTripletasDuplicadas
FROM (
    SELECT ProductKey, WeekCode, Region
    FROM fact.FACT_SALES
    GROUP BY ProductKey, WeekCode, Region
    HAVING COUNT(*) > 1
) d;

-- Rango de fechas y semanas (calendario y fact)
SELECT MIN(FullDate) AS MinDate, MAX(FullDate) AS MaxDate, COUNT(*) AS Weeks
FROM dim.DIM_CALENDAR;

SELECT MIN(WeekCode) AS MinWeekFact, MAX(WeekCode) AS MaxWeekFact, COUNT(DISTINCT WeekCode) AS WeeksInFact
FROM fact.FACT_SALES;

-- Spot-check de consistencia: FACT vs STAGING (mismo grano) */
;WITH StgClean AS (
    SELECT 
        LTRIM(RTRIM([WEEK]))                 AS WeekCode,
        LTRIM(RTRIM([ITEM_CODE]))            AS ItemCode,
        LTRIM(RTRIM([REGION]))               AS Region,
        TRY_CONVERT(DECIMAL(18,4), REPLACE(REPLACE(REPLACE(REPLACE([TOTAL_UNIT_SALES],'"',''), ' ', ''), CHAR(160), ''), ',', '.')) AS TUS,
        TRY_CONVERT(DECIMAL(18,4), REPLACE(REPLACE(REPLACE(REPLACE([TOTAL_VALUE_SALES],'"',''), ' ', ''), CHAR(160), ''), ',', '.')) AS TVS,
        TRY_CONVERT(DECIMAL(18,4), REPLACE(REPLACE(REPLACE(REPLACE([TOTAL_UNIT_AVG_WEEKLY_SALES],'"',''), ' ', ''), CHAR(160), ''), ',', '.')) AS TUAW
    FROM stg.FACT_SALES
),
Map AS (
    SELECT p.ProductKey, s.WeekCode, s.Region, s.TUS, s.TVS, s.TUAW
    FROM StgClean s
    JOIN dim.DIM_PRODUCT p ON p.ItemCode = s.ItemCode
)
SELECT TOP (10)
    f.ProductKey, f.WeekCode, f.Region,
    f.TotalUnitSales  AS Fact_TUS,  m.TUS  AS Stg_TUS,
    f.TotalValueSales AS Fact_TVS,  m.TVS  AS Stg_TVS,
    f.TotalUnitAvgWeeklySales AS Fact_TUAW, m.TUAW AS Stg_TUAW
FROM fact.FACT_SALES f
JOIN Map m
  ON m.ProductKey = f.ProductKey
 AND m.WeekCode   = f.WeekCode
 AND m.Region     = f.Region
WHERE (ABS(ISNULL(f.TotalUnitSales,0)         - ISNULL(m.TUS,0))  > 0.0001
    OR ABS(ISNULL(f.TotalValueSales,0)        - ISNULL(m.TVS,0))  > 0.0001
    OR ABS(ISNULL(f.TotalUnitAvgWeeklySales,0)- ISNULL(m.TUAW,0)) > 0.0001);

-- Perfil rápido (distribución por semana y región)
SELECT TOP (10) WeekCode, COUNT(*) AS Rows, 
       SUM(TotalUnitSales) AS SumTUS,
       SUM(TotalValueSales) AS SumTVS
FROM fact.FACT_SALES
GROUP BY WeekCode
ORDER BY WeekCode;

SELECT TOP (10) Region, COUNT(*) AS Rows,
       SUM(TotalUnitSales) AS SumTUS,
       SUM(TotalValueSales) AS SumTVS
FROM fact.FACT_SALES
GROUP BY Region
ORDER BY Region;







---------- e) Uniones entre tablas ----------
-- Vista de trabajo (join una sola vez)
USE EmpresaAliadaDW;
GO

IF OBJECT_ID('dbo.vw_Sales', 'V') IS NOT NULL
    DROP VIEW dbo.vw_Sales;
GO

CREATE VIEW dbo.vw_Sales
AS
SELECT
    c.[Year],
    c.WeekCode,
    c.FullDate,
    f.Region,
    p.ProductKey,
    p.ItemCode,
    p.ItemDescription,
    p.Brand,
    p.Manufacturer,
    p.CategoryID,
    cat.CategoryName,
    f.TotalUnitSales,
    f.TotalValueSales,
    f.TotalUnitAvgWeeklySales
FROM fact.FACT_SALES     AS f
JOIN dim.DIM_PRODUCT     AS p   ON p.ProductKey  = f.ProductKey
JOIN dim.DIM_CATEGORY    AS cat ON cat.CategoryID= p.CategoryID
JOIN dim.DIM_CALENDAR    AS c   ON c.WeekCode    = f.WeekCode;
GO


-- Parámetros del análisis (ajústalos)
USE EmpresaAliadaDW;
SET NOCOUNT ON;

DECLARE @YearFrom   smallint      = 2021;
DECLARE @YearTo     smallint      = 2022;
DECLARE @RegionLike nvarchar(100) = NULL; 

-- Visualizar el JOIN base
SELECT TOP (20)
       s.*
FROM dbo.vw_Sales AS s
ORDER BY s.FullDate, s.Region, s.ItemCode;




-- Ventas por categoría y año
SELECT
    [Year],
    CategoryID,
    CategoryName,
    SUM(TotalUnitSales)                               AS Units,
    SUM(TotalValueSales)                              AS Value,
    CAST(SUM(TotalValueSales)/NULLIF(SUM(TotalUnitSales),0) AS decimal(18,4)) AS AvgPrice
FROM dbo.vw_Sales
WHERE [Year] BETWEEN @YearFrom AND @YearTo
  AND (@RegionLike IS NULL OR Region LIKE @RegionLike)
GROUP BY [Year], CategoryID, CategoryName
ORDER BY [Year], Value DESC;

-- Ventas por región y semana
SELECT
    [Year], WeekCode, Region,
    SUM(TotalUnitSales)  AS Units,
    SUM(TotalValueSales) AS Value
FROM dbo.vw_Sales
WHERE [Year] BETWEEN @YearFrom AND @YearTo
  AND (@RegionLike IS NULL OR Region LIKE @RegionLike)
GROUP BY [Year], WeekCode, Region
ORDER BY [Year], MIN(FullDate), Region;

-- Top 15 productos por valor
SELECT TOP (15)
    ItemCode, ItemDescription, Brand, CategoryName,
    SUM(TotalValueSales) AS Value,
    SUM(TotalUnitSales)  AS Units
FROM dbo.vw_Sales
WHERE [Year] BETWEEN @YearFrom AND @YearTo
  AND (@RegionLike IS NULL OR Region LIKE @RegionLike)
GROUP BY ItemCode, ItemDescription, Brand, CategoryName
ORDER BY Value DESC;

-- Ticket promedio (Valor/Unidad) por región y año
SELECT
    [Year],
    Region,
    SUM(TotalValueSales) AS Value,
    SUM(TotalUnitSales)  AS Units,
    CAST(SUM(TotalValueSales)/NULLIF(SUM(TotalUnitSales),0) AS decimal(18,4)) AS AvgTicket
FROM dbo.vw_Sales
WHERE [Year] BETWEEN @YearFrom AND @YearTo
  AND (@RegionLike IS NULL OR Region LIKE @RegionLike)
GROUP BY [Year], Region
ORDER BY [Year], AvgTicket DESC;


-- Top 15 productos por valor dentro de una región y año
SELECT TOP (15)
    ItemCode, ItemDescription, Brand, CategoryName,
    SUM(TotalValueSales) AS Value,
    SUM(TotalUnitSales)  AS Units
FROM dbo.vw_Sales
WHERE [Year] BETWEEN @YearFrom AND @YearTo
  AND (@RegionLike IS NULL OR Region LIKE @RegionLike)
GROUP BY ItemCode, ItemDescription, Brand, CategoryName
ORDER BY Value DESC;







-- Alternativa aún más robusta (opcional): un procedimiento almacenado
USE EmpresaAliadaDW;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Insights
    @YearFrom   smallint,
    @YearTo     smallint,
    @RegionLike nvarchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Ejemplo: ventas por categoría y año
    SELECT [Year], CategoryID, CategoryName,
           SUM(TotalUnitSales) AS Units,
           SUM(TotalValueSales) AS Value,
           CAST(SUM(TotalValueSales)/NULLIF(SUM(TotalUnitSales),0) AS decimal(18,4)) AS AvgPrice
    FROM dbo.vw_Sales
    WHERE [Year] BETWEEN @YearFrom AND @YearTo
      AND (@RegionLike IS NULL OR Region LIKE @RegionLike)
    GROUP BY [Year], CategoryID, CategoryName
    ORDER BY [Year], Value DESC;

    -- (añade aquí los demás SELECTs que quieras devolver)
END
GO

-- Ejemplos de uso:
EXEC dbo.usp_Insights @YearFrom = 2021, @YearTo = 2022, @RegionLike = NULL;
EXEC dbo.usp_Insights @YearFrom = 2021, @YearTo = 2022, @RegionLike = N'%AREA 1%';

















