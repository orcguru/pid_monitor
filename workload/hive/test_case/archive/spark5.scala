import org.apache.spark.sql.hive.HiveContext
val sqlContext = new HiveContext(sc)
val dbName = sys.env("DB_NAME")
sqlContext.sql(s"USE " + dbName)
val result=sqlContext.sql(s"select count(*) from os_order_item where gprice > 100.0 and gprice < 150.0")
result.show()
sc.stop()
exit()
