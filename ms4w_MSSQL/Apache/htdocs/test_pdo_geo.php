<!DOCTYPE html>
<html>
<head>
    <title>Testing SpatiaLite on PHP using PDO</title>
</head>
<body>
    <h1>Testing SpatiaLite on PHP using PDO</h1>

<?php
try {
    # connecting to SQLite in-memory database
    $db = new PDO('sqlite::memory:');
    
    # Enabling exceptions on errors
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    # loading SpatiaLite extension
    $db->exec("PRAGMA foreign_keys = ON");
    $db->exec("PRAGMA trusted_schema = ON");
    $db->exec("PRAGMA database_list");

    # Load the SpatiaLite extension
    $db->sqliteCreateFunction('enable_extension', 'this->sqlite3_enable_load_extension', 1);
    //$db->sqliteCreateFunction('load_extension', 'sqlite3_load_extension', 1);
    $db->query("SELECT load_extension('libspatialite.dll')");

    # enabling Spatial Metadata
    $db->exec("SELECT InitSpatialMetadata(1)");

    # reporting SQLite and SpatiaLite version
    $rs = $db->query('SELECT sqlite_version()');
    $row = $rs->fetch(PDO::FETCH_NUM);
    print "<h3>SQLite version: $row[0]</h3>";

    $rs = $db->query('SELECT spatialite_version()');
    $row = $rs->fetch(PDO::FETCH_NUM);
    print "<h3>SpatiaLite version: $row[0]</h3>";

    # creating a POINT table
    $db->exec("CREATE TABLE test_pt (id INTEGER NOT NULL PRIMARY KEY, name TEXT NOT NULL)");
    $db->exec("SELECT AddGeometryColumn('test_pt', 'geom', 4326, 'POINT', 'XY')");

    # creating a LINESTRING table
    $db->exec("CREATE TABLE test_ln (id INTEGER NOT NULL PRIMARY KEY, name TEXT NOT NULL)");
    $db->exec("SELECT AddGeometryColumn('test_ln', 'geom', 4326, 'LINESTRING', 'XY')");

    # creating a POLYGON table
    $db->exec("CREATE TABLE test_pg (id INTEGER NOT NULL PRIMARY KEY, name TEXT NOT NULL)");
    $db->exec("SELECT AddGeometryColumn('test_pg', 'geom', 4326, 'POLYGON', 'XY')");

    # inserting some POINTs
    $db->beginTransaction();
    for ($i = 0; $i < 10000; $i++) {
        $id = $i + 1;
        $name = "test POINT #$id";
        $geom = "GeomFromText('POINT(" . ($i / 1000.0) . " " . ($i / 1000.0) . ")', 4326)";
        $db->exec("INSERT INTO test_pt (id, name, geom) VALUES ($id, '$name', $geom)");
    }
    $db->commit();

    # checking POINTs
    $rs = $db->query("SELECT DISTINCT Count(*), ST_GeometryType(geom), ST_Srid(geom) FROM test_pt");
    $row = $rs->fetch(PDO::FETCH_NUM);
    print "<h3>Inserted $row[0] entities of type $row[1] SRID=$row[2]</h3>";

    # inserting some LINESTRINGs
    $sql = "INSERT INTO test_ln (id, name, geom) VALUES (?, ?, GeomFromText(?, 4326))";
    $stmt = $db->prepare($sql);
    $db->beginTransaction();
    for ($i = 0; $i < 10000; $i++) {
        $id = $i + 1;
        $name = "test LINESTRING #$id";
        $geom = "LINESTRING(" . 
                (($i % 2) == 1 ?
                    "-180.0 -90.0, " . (-10.0 - ($i / 1000.0)) . " " . (-10.0 - ($i / 1000.0)) . ", " . 
                    (-10.0 - ($i / 1000.0)) . " " . (10.0 + ($i / 1000.0)) . ", " . 
                    (10.0 + ($i / 1000.0)) . " " . (10.0 + ($i / 1000.0)) . ", 180.0 90.0" :
                    (-10.0 - ($i / 1000.0)) . " " . (-10.0 - ($i / 1000.0)) . ", " . 
                    (10.0 + ($i / 1000.0)) . " " . (10.0 + ($i / 1000.0))) . ")";
        $stmt->execute([$id, $name, $geom]);
    }
    $db->commit();

    # checking LINESTRINGs
    $rs = $db->query("SELECT DISTINCT Count(*), ST_GeometryType(geom), ST_Srid(geom) FROM test_ln");
    $row = $rs->fetch(PDO::FETCH_NUM);
    print "<h3>Inserted $row[0] entities of type $row[1] SRID=$row[2]</h3>";

    # inserting some POLYGONs
    $sql = "INSERT INTO test_pg (id, name, geom) VALUES (?, ?, GeomFromText(?, 4326))";
    $stmt = $db->prepare($sql);
    $db->beginTransaction();
    for ($i = 0; $i < 10000; $i++) {
        $id = $i + 1;
        $name = "test POLYGON #$id";
        $geom = "POLYGON((" .
                (-10.0 - ($i / 1000.0)) . " " . (-10.0 - ($i / 1000.0)) . ", " .
                (10.0 + ($i / 1000.0)) . " " . (-10.0 - ($i / 1000.0)) . ", " .
                (10.0 + ($i / 1000.0)) . " " . (10.0 + ($i / 1000.0)) . ", " .
                (-10.0 - ($i / 1000.0)) . " " . (10.0 + ($i / 1000.0)) . ", " .
                (-10.0 - ($i / 1000.0)) . " " . (-10.0 - ($i / 1000.0)) . "))";
        $stmt->execute([$id, $name, $geom]);
    }
    $db->commit();

    # checking POLYGONs
    $rs = $db->query("SELECT DISTINCT Count(*), ST_GeometryType(geom), ST_Srid(geom) FROM test_pg");
    $row = $rs->fetch(PDO::FETCH_NUM);
    print "<h3>Inserted $row[0] entities of type $row[1] SRID=$row[2]</h3>";

    # closing the DB connection
    $db = null;

} catch (PDOException $e) {
    print "Error!: " . $e->getMessage() . "<br/>";
    die();
}
?>

</body>
</html>
