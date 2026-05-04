# CISC 886 - Project: End-to-End Cloud-Based Tech Chatbot Assistant 

## Author Information
 **Name**: **Kerolos_Zaka**

## 1. Project Overview
This project fulfills the requirements for the **CISC 886 Cloud Computing** course project. It implements a fully isolated, end-to-end cloud-native pipeline designed to preprocess large-scale data, fine-tune a Large Language Model (LLM), and deploy it as a live web application accessible via a browser.

The architecture follows a cost-optimized, hybrid development-to-production lifecycle:

* **Data Preprocessing at Scale**: An **AWS EMR** cluster running Apache Spark is used to clean, filter, and transform raw StackExchange/RedPajama QA data into high-quality training records. To remain within account resource limits, the cluster is configured with exactly 2 nodes (`r8g.xlarge`).
* **Efficient Model Fine-Tuning**: A local, isolated **Docker environment** running the official `unsloth/unsloth` image leverages the compute power of an **NVIDIA RTX 2000 Ada Generation** GPU. This bypasses local OS-specific library dependency issues while enabling parameter-efficient fine-tuning via **QLoRA (4-bit quantization)** on the Meta-Llama-3-8B model.
* **Hosted Deployment**: The trained weights are merged with the base model, converted to the GGUF format for optimal CPU inference, and transferred to an **AWS EC2 instance** (`m5.xlarge` running Ubuntu Server 22.04 LTS). The model is served using a CPU-optimized **llama.cpp** inference container to maintain a highly reliable, low-cost production footprint.
* **Interactive Web Interface**: A public **Streamlit** user interface acts as the frontend, allowing users to interact directly with the fine-tuned assistant over the web via port `8501`.


   In strict compliance with the course's resource naming policy, all AWS resources created during this project—including the custom VPC, subnets, route tables, security groups, EMR cluster, S3 bucket, and EC2 instance—are prefixed with the Queen's NetID to ensure complete isolation and ease of grading.
---

## 3. Step-by-Step Replication Guide

### Phase 1: Custom VPC & Networking (Section 2)

To isolate the infrastructure from the default AWS VPC, a custom VPC network was created.

#### Replication Steps using Terraform:
1. Navigate to the `terraform/` directory of this repository:
   ```bash
   cd terraform/
   ```
2. Initialize and apply the Terraform configuration:
   ```bash
   terraform init
   terraform apply -var="netid=[your-netid]"
   ```

#### Network Design Configuration Summary:
* **CIDR Block**: `10.0.0.0/16`
* **Subnets**:
  * **Public Subnet**: `10.0.1.0/24` (Hosts the public EC2 Chat Interface & Internet Gateway)
  * **Private Subnet**: `10.0.2.0/24` (Hosts the EMR worker nodes safely away from the internet)
* **Route Tables**: Attached an **Internet Gateway (IGW)** to the public route table to map traffic to the public internet.
* **Security Groups**:
  * **Port 22 (SSH)**: Limited to the administrator's IP address for security management.
  * **Port 8501**: Open to the public internet (`0.0.0.0/0`) to serve the Streamlit chat UI.
  * **Port 8000**: Open internally for FastAPI / serving traffic.

---

### Phase 2: Distributed Data Preprocessing with Apache Spark on EMR (Section 4)

Large raw data files are ingested and processed using distributed computing over an AWS EMR cluster.

#### 1. Cluster Provisioning:
Deploy an EMR Cluster via the AWS CLI or AWS Console with the following specifications:
* **EMR Release**: `emr-7.13.0`
* **Cluster Nodes**: 1 Primary Master Node, 1 Core Node (**2 Nodes Total** to stay within account and resource limits).
* **Instance Type**: `r8g.xlarge`.

#### 2. Run the PySpark Preprocessing Code:
The raw data files are cleaned, transformed, and coalesced into a single JSONL output using the committed script:
```bash
# Upload code to the master node or submit as an EMR step
aws s3 cp s3://[your-netid]-raw-data/ scripts/ --recursive
```
*The PySpark cleaning script filters out malformed strings, drops null values, performs token length filtering, and writes the output as a clean `.jsonl` file to S3.*

#### 3. Cluster Teardown:
Immediately terminate the cluster after your job steps finish to prevent any extra compute costs:
```bash
aws emr terminate-clusters --cluster-ids [your-cluster-id]
```

---

### Phase 3: Model & Dataset Selection (Section 3)

#### Model Metadata:
* **Model Name**: Meta-Llama-3-8B
* **Parameter Count**: 8 Billion parameters
* **Source**: [Hugging Face Meta-Llama-3-8B](https://huggingface.co/meta-llama/Meta-Llama-3-8B)
* **License**: Meta Llama 3 Community License Agreement
* **Justification**: The 8B parameter model strikes an ideal balance between domain fit and the VRAM capacity of the local GPU hardware used for training.

#### Dataset Metadata:
* **Dataset**: Filtered StackExchange / RedPajama QA Subset
* **Data Volume**: 150,000 highly curated text records
* **Validation Strategy**: 70% Training split, 30% Validation split. Data leakage is prevented by isolating timestamps and deduplicating data hashes prior to the split.

---

### Phase 4: Parameter-Efficient Fine-Tuning (Section 5)

Fine-tuning is executed using a parameter-efficient approach inside a local Docker container.

#### Environment Isolation via Docker
To completely bypass Windows-specific library dependency issues (version conflicts between Python, PyTorch, xFormers, and CUDA), we utilized the official Unsloth Docker image:
👉 **[https://hub.docker.com/r/unsloth/unsloth](https://hub.docker.com/r/unsloth/unsloth)**

This isolated image comes pre-configured with matched libraries, ensuring environment consistency and zero dependency issues during local execution.

#### 1. Launch the Isolated Training Environment:
```powershell
docker run -d `
  --name unsloth_trainer `
  --gpus all `
  -p 8888:8888 `
  -v "C:\Users\braveboy911\Downloads:/workspace/data" `
  unsloth/unsloth:latest
```

#### 2. Execute Training Notebook:
Load `final.ipynb` in your Jupyter instance (`http://localhost:8888`) and run the cells:
* It performs 4-bit quantization (QLoRA) using the `peft` and `transformers` libraries.

#### Hyperparameter Configuration Summary:
* **Learning Rate**: `2e-4`
* **Batch Size**: `4` per device (with gradient accumulation steps = `4`)
* **Epochs**: `1`
* **Optimizer**: `paged_adamw_8bit`
* **LoRA Rank ($r$)**: `16`
* **LoRA Alpha ($\alpha$)**: `16`
* **Target Modules**: `q_proj`, `k_proj`, `v_proj`, `o_proj`

#### 3. Merge Weights Post-Training:
Because training occurs in a 4-bit base environment, the adapter weights must be re-loaded and merged into an FP16 base model to produce a standalone model artifact:
```python
import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM

base_model = AutoModelForCausalLM.from_pretrained("/workspace/data/Meta-Llama-3-8B", torch_dtype=torch.float16)
model = PeftModel.from_pretrained(base_model, "/workspace/data/Meta_Llama_finetuned")
merged_model = model.merge_and_unload()
merged_model.save_pretrained("/workspace/data/Llama-3-8B-Final-Merged")
```

---

### Phase 5: Production Deployment on AWS EC2 (Section 6)

The merged standalone model weights are converted to GGUF format for highly optimized, cost-efficient CPU deployment on a standard EC2 instance.

#### Instance Specifications:
* **Instance Type**: `m5.xlarge` (4 vCPUs, 16GB RAM)
* **AMI**: Ubuntu Server 22.04 LTS AMI

#### Installation & Execution Commands on EC2:
1. Connect via SSH and install Docker:
   ```bash
   # Update system and install Docker
   sudo apt-get update && sudo apt-get upgrade -y
   curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
   sudo usermod -aG docker $USER
   # Re-login or run: newgrp docker
   ```
2. Pull the model weights from S3 to your EC2 storage:
   ```bash
   aws s3 cp s3://[your-netid]-cisc886-project-dataa/finetunned_model/ ./model/ --recursive
   ```
3. Spin up an optimized CPU inference engine container using **llama.cpp** to serve the GGUF model:
   ```bash
   docker run -d \
     -p 8000:8000 \
     -v $(pwd)/model:/workspace/model \
     ghcr.io/ggerganov/llama.cpp:server \
     -m /workspace/model/llama-3-8b-merged.Q4_K_M.gguf \
     -c 2048 \
     --host 0.0.0.0 \
     --port 8000
   ```
4. Verify the deployment using a `curl` call:
   ```bash
   curl http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Explain Cloud Computing"}], "max_tokens": 50}'
   ```

---

### Phase 6: Web Chat Interface Setup (Section 7)

The frontend user interface is implemented using **Streamlit**, allowing users to prompt the model through their browser.

#### 1. Streamlit Application Code (`app.py`)
```python
import streamlit as st
import requests
import json

# 1. Page Configuration
st.set_page_config(
    page_title="Queen's AI Assistant",
    page_icon="👑",
    layout="wide"
)

# 2. Custom CSS for a "Modern Dark" or "Cloud" Look
st.markdown("""
    <style>
    .stChatMessage {
        border-radius: 15px;
        padding: 10px;
        margin-bottom: 10px;
    }
    .main {
        background-color: #0e1117;
    }
    </style>
    """, unsafe_allow_html=True)

# 3. Sidebar for System Info & Settings
with st.sidebar:
    st.image("https://cdn-icons-png.flaticon.com/512/6295/6295417.png", width=100)
    st.title("System Control")
    st.info("🚀 **Host:** m5.xlarge\n\n🧠 **Model:** Llama 3 (mybot)")

    if st.button("Clear Chat History"):
        st.session_state.messages = []
        st.rerun()

    st.divider()
    st.caption("Status: Ollama Server Active ✅")

# 4. Header Section
col1, col2 = st.columns([1, 5])
with col1:
    st.write("")  # Spacer
with col2:
    st.title("👑 Queen's Cloud Assistant")
    st.write("Experience the power of local LLMs on AWS.")

st.divider()

# 5. Chat Logic
if "messages" not in st.session_state:
    st.session_state.messages = []

# Display messages with specific avatars
for message in st.session_state.messages:
    avatar = "👤" if message["role"] == "user" else "🤖"
    with st.chat_message(message["role"], avatar=avatar):
        st.markdown(message["content"])

# Input handling
if prompt := st.chat_input("Ask me anything about AWS or Cloud..."):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user", avatar="👤"):
        st.markdown(prompt)

    with st.chat_message("assistant", avatar="🤖"):
        response_placeholder = st.empty()
        full_response = ""

        try:
            response = requests.post(
                "http://localhost:11434/api/generate",
                json={"model": "mybot", "prompt": prompt, "stream": True},
                timeout=300,
                stream=True
            )
            if response.status_code == 200:
                for line in response.iter_lines():
                    if line:
                        chunk = json.loads(line.decode('utf-8'))
                        token = chunk.get("response", "")
                        full_response += token
                        response_placeholder.markdown(full_response + "┃")

                response_placeholder.markdown(full_response)
                st.session_state.messages.append({"role": "assistant", "content": full_response})
            else:
                st.error(f"❌ Server Error: {response.status_code}")
        except Exception as e:
            st.error(f"⚠️ Connection Error: {e}")
```

#### 2. Run the Interface:
To launch the Streamlit server on the `m5.xlarge` instance:
```bash
streamlit run app.py --server.port 8501
```

---

## 4. Cost Summary Table

The approximate breakdown of AWS service expenses for distributed processing and CPU-optimized deployment is summarized below:

| Service | Purpose | Quantity / Runtime | Unit Rate | Estimated Total Cost (USD) |
| :--- | :--- | :--- | :--- | :--- |
| **AWS EMR** | Distributed Spark preprocessing | 2 × `r8g.xlarge` nodes total for 1.5 hours | $0.29 / hour | **$0.87** |
| **AWS S3** | Data Lake storage of raw & processed files | **20 GB** stored for 1 month | $0.023 / GB | **$0.46** |
| **AWS EC2** | Model Inference Serving | 1 × `m5.xlarge` for 5 hours | $0.192 / hour | **$0.96** |
| **AWS VPC** | Elastic IP address allocation | 1 EIP used for NAT Gateway for 6 hours | $0.005 / hour | **$0.03** |
| **Total Project Spend** | | | | **$2.32** |

---

## Repository Structure Checklist
```
├── terraform/                   # AWS VPC configuration files
│   └── main.tf
├── spark_clean.py               # EMR PySpark script
├── final.ipynb                  # Fine-tuning notebook
├── app.py                       # Streamlit application
├── README.md                    # Project replication guide
└── .gitignore
```
