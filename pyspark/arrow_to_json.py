from pyspark.sql import SparkSession
import pyarrow.ipc as ipc
import io

spark = SparkSession.builder.appName("ArrowToJsonRaw").getOrCreate()

# 1. Read binary files from S3
raw_data = spark.sparkContext.binaryFiles("s3://25hnxx-cisc886-project-data/raw/stackexchange_redpajamas/*.arrow")

def process_arrow_binary(binary_tuple):
    # binary_tuple = (file_path, binary_content)
    file_content = io.BytesIO(binary_tuple[1])
    try:
        reader = ipc.open_stream(file_content)
        table = reader.read_all()
        # Convert the 'text' column to a list of dicts for Spark
        return [row.as_py() for row in table.column("text")]
    except:
        return []

# 2. Use RDD to process the binary streams and convert to DataFrame
raw_texts_rdd = raw_data.flatMap(process_arrow_binary)
df = raw_texts_rdd.map(lambda x: (x,)).toDF(["raw_text"])

# 3. Save as unprocessed JSON
output_path = "s3://25hnxx-cisc886-project-data/unprocessed_json/"
df.write.mode("overwrite").json(output_path)
