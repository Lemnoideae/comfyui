#!/bin/bash

# ==============================================================================
# ComfyUI 수동 설정 스크립트 (For ai-dock / vast.ai)
# ==============================================================================

# 작업 경로 설정 (ai-dock 기본 경로 기준)
WORKSPACE="/workspace"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
WEB_SCRIPTS_DIR="/opt/ComfyUI/web/scripts" # ai-dock의 기본 웹 경로

# 토큰이 있다면 환경변수로 미리 export 하세요 (ex: export HF_TOKEN="your_token")
HF_TOKEN=${HF_TOKEN:-""}
CIVITAI_TOKEN=${CIVITAI_TOKEN:-""}

# ------------------------------------------------------------------------------
# 설정 값 (패키지, 노드, 모델)
# ------------------------------------------------------------------------------

DEFAULT_WORKFLOW="https://drive.google.com/uc?export=download&id=1q8az1MLDep0j-UHebsMYCz0pMVtZADMY"

PIP_PACKAGES=(
    "triton"
    "sageattention"
)

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/ruwwww/ComfyUI-Spectrum-sdxl"
    "https://github.com/BobJohnson24/ComfyUI-INT8-Fast"
    "https://github.com/sorryhyun/ComfyUI-Spectrum-KSampler"
    "https://github.com/AdamNizol/ComfyUI-Anima-Enhancer"
    "https://github.com/newtextdoc1111/ComfyUI-Autocomplete-Plus"
    "https://github.com/willmiao/ComfyUI-Lora-Manager"
    "https://github.com/granatta000/anima-artist-mixer"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/diffusion_models/anima-base-v1.0.safetensors"
)

TEXT_ENCODERS=(
    "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors"
)

# ------------------------------------------------------------------------------
# 함수 정의
# ------------------------------------------------------------------------------

# 1. Python/PIP 환경 찾기 (ai-dock 환경 호환성 확보)
function setup_python_env() {
    echo -e "\n[INFO] Python 환경을 찾습니다..."
    if [ -f "/opt/environments/python/comfyui/bin/python" ]; then
        PYTHON_CMD="/opt/environments/python/comfyui/bin/python"
    elif command -v micromamba &> /dev/null; then
        PYTHON_CMD="micromamba run -n comfyui python"
    else
        PYTHON_CMD="python3"
    fi
    echo "[INFO] 사용할 Python: $PYTHON_CMD"
}

# 2. PIP 패키지 설치
function install_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        echo -e "\n[INFO] PIP 패키지를 설치합니다..."
        $PYTHON_CMD -m pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

# 3. 커스텀 노드 설치
function install_nodes() {
    echo -e "\n[INFO] 커스텀 노드를 설치/업데이트 합니다..."
    local CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
    mkdir -p "$CUSTOM_NODES_DIR"

    for repo in "${NODES[@]}"; do
        dir_name="${repo##*/}"
        # .git 확장자 제거
        dir_name="${dir_name%.git}"
        path="${CUSTOM_NODES_DIR}/${dir_name}"
        
        if [[ -d "$path" ]]; then
            echo "[INFO] 업데이트 중: ${dir_name}"
            (cd "$path" && git pull)
        else
            echo "[INFO] 다운로드 중: ${dir_name}"
            git clone "$repo" "$path" --recursive
        fi

        # requirements.txt 설치
        if [[ -f "${path}/requirements.txt" ]]; then
            echo "[INFO] ${dir_name}의 requirements.txt 설치 중..."
            $PYTHON_CMD -m pip install --no-cache-dir -r "${path}/requirements.txt"
        fi
    done
}

# 4. 모델 다운로드 함수
function download_models() {
    local target_dir="$1"
    shift
    local urls=("$@")

    if [[ ${#urls[@]} -eq 0 ]]; then return 0; fi

    mkdir -p "$target_dir"
    echo -e "\n[INFO] ${target_dir} 경로에 ${#urls[@]}개의 모델을 다운로드합니다..."

    for url in "${urls[@]}"; do
        echo " -> Downloading: $url"
        
        local auth_header=""
        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            auth_header="--header=Authorization: Bearer $HF_TOKEN"
        elif [[ -n "$CIVITAI_TOKEN" && "$url" =~ civitai\.com ]]; then
            auth_header="--header=Authorization: Bearer $CIVITAI_TOKEN"
        fi

        # wget을 이용한 이어받기(-c) 및 기존파일 덮어쓰기 방지(-nc)
        if [[ -n "$auth_header" ]]; then
            wget $auth_header -qnc --content-disposition --show-progress -P "$target_dir" "$url"
        else
            wget -qnc --content-disposition --show-progress -P "$target_dir" "$url"
        fi
    done
}

# 5. 기본 워크플로우 설정
function setup_default_workflow() {
    if [[ -n "$DEFAULT_WORKFLOW" ]]; then
        echo -e "\n[INFO] 기본 워크플로우를 설정합니다..."
        # 디렉토리가 존재하는지 확인 (ai-dock 버전에 따라 다를 수 있음)
        if [[ -d "$WEB_SCRIPTS_DIR" ]]; then
            workflow_json=$(curl -sL "$DEFAULT_WORKFLOW")
            if [[ -n "$workflow_json" && "$workflow_json" != *"html"* ]]; then
                echo "export const defaultGraph = $workflow_json;" > "${WEB_SCRIPTS_DIR}/defaultGraph.js"
                echo "[INFO] defaultGraph.js 업데이트 완료."
            else
                echo "[WARN] 워크플로우 JSON 다운로드 실패 (구글 드라이브 권한을 확인하세요)."
            fi
        else
            echo "[WARN] $WEB_SCRIPTS_DIR 경로가 존재하지 않아 기본 워크플로우를 설정할 수 없습니다."
        fi
    fi
}

# ------------------------------------------------------------------------------
# 메인 실행 부
# ------------------------------------------------------------------------------

echo "=============================================="
echo " ComfyUI 자동 설정 스크립트를 시작합니다.     "
echo "=============================================="

# 디렉토리 존재 유무 체크
if [[ ! -d "$COMFYUI_DIR" ]]; then
    echo "[ERROR] $COMFYUI_DIR 디렉토리가 존재하지 않습니다."
    echo "[ERROR] ComfyUI가 설치된 경로가 맞는지 확인해주세요."
    exit 1
fi

setup_python_env
install_nodes
install_pip_packages

download_models "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
download_models "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODERS[@]}"
download_models "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"

setup_default_workflow

echo -e "\n=============================================="
echo " 모든 설치 및 다운로드가 완료되었습니다! "
echo " ComfyUI를 재시작해 주세요. "
echo "=============================================="
