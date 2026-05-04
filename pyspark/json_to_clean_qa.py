from pyspark.sql import SparkSession
from pyspark.sql.functions import col, udf
from pyspark.sql.types import StructType, StructField, StringType
import re

spark = SparkSession.builder.appName("TechSupportQAExtractor").getOrCreate()

# STEP 1: Define the cleaning logic as a Spark UDF
def extract_qa_logic(text):
    if not text or "Q:" not in text or "A:" not in text:
        return None
    
    try:
        parts = text.split("A:")
        question = parts[0].replace("Q:", "").strip()
        answer = re.split(r"\nA:", parts[1])[0].strip()

        # Quality Filters
        if 10 < len(question) and 20 < len(answer) < 2000:
            return (question, answer)
    except:
        pass
    return None

# Define Schema for the output of the UDF
schema = StructType([
    StructField("instruction", StringType(), False),
    StructField("response", StringType(), False)
])

extract_udf = udf(extract_qa_logic, schema)

# STEP 2: Load the unprocessed JSON from Step 1
raw_df = spark.read.json("s3://25hnxx-cisc886-project-data/unprocessed_json/")

# STEP 3: Apply transformation and filter out nulls
final_df = raw_df.withColumn("qa", extract_udf(col("raw_text"))) \
                 .select("qa.instruction", "qa.response") \
                 .filter(col("instruction").isNotNull())

# STEP 4: Merge into 1 partition and save
final_output_path = "s3://25hnxx-cisc886-project-data/processed/"

# coalesce(1) tells Spark to pull all data onto one node to create a single file
final_df.coalesce(1).write.mode("overwrite").json(final_output_path)

print(f"Final dataset merged and saved to: {final_output_path}")
