#!/bin/bash

# ==============================================================================
# Script para mesclar e limpar arquivos de favoritos (.html)
# Uso: ./merge_bookmarks.sh <arquivo_saida.html> <diretorio_ou_arquivo_1> [arq_2...]
# ==============================================================================

# 1. Checagem de dependência: Verifica se o Python 3 está instalado
if ! command -v python3 &> /dev/null; then
    echo "Erro: python3 é necessário para processar o HTML com segurança." >&2
    exit 1
fi

# 2. Validação de argumentos mínimos
if [ "$#" -lt 2 ]; then
    echo "Uso incorreto."
    echo "Modo de usar: $0 <arquivo_saida.html> <diretorio_ou_arquivo_1> [arquivo_2 ...]"
    echo "Exemplo: $0 meus_favoritos.html ~/Downloads/pasta_bookmarks/ arquivo_solto.html"
    exit 1
fi

OUTPUT_FILE="$1"
shift

# 3. Coleta e validação dos arquivos de entrada (suporta arquivos individuais e diretórios)
INPUT_FILES=()
for arg in "$@"; do
    if [ -d "$arg" ]; then
        while IFS=read -r -d '' file; do
            INPUT_FILES+=("$file")
        done < <(find "$arg" -name "*.html" -type f -print0)
    elif [ -f "$arg" ]; then
        INPUT_FILES+=("$arg")
    else
        echo "Aviso: Caminho ignorado (não é um arquivo .html nem diretório válido): $arg" >&2
    fi
done

if [ "${#INPUT_FILES[@]}" -eq 0 ]; then
    echo "Erro: Nenhum arquivo .html válido foi encontrado nos caminhos fornecidos." >&2
    exit 1
fi

echo "Processando ${#INPUT_FILES[@]} arquivo(s) encontrado(s)..."

# 4. Bloco Python embutido para fazer o parsing, deduplicação e geração do HTML final
python3 - "$OUTPUT_FILE" "${INPUT_FILES[@]}" << 'EOF'
import sys
from html.parser import HTMLParser

output_file = sys.argv[1]
input_files = sys.argv[2:]

categories = {}
seen_urls = set()

class BookmarkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.category_stack = []
        self.in_h3 = False
        self.current_h3_text = ""
        self.current_a_href = None
        self.current_a_title = ""
        self.in_a = False

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        attrs_dict = dict(attrs)
        if tag == 'h3':
            self.in_h3 = True
            self.current_h3_text = ""
        elif tag == 'a':
            if 'href' in attrs_dict:
                self.current_a_href = attrs_dict['href']
                self.in_a = True
                self.current_a_title = ""
        elif tag == 'dl':
            if self.current_h3_text:
                self.category_stack.append(self.current_h3_text.strip())
                self.current_h3_text = ""

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag == 'h3':
            self.in_h3 = False
        elif tag == 'a':
            if self.in_a and self.current_a_href:
                cat_name = " / ".join(self.category_stack) if self.category_stack else "Outros"
                title = self.current_a_title.strip() or self.current_a_href
                
                if cat_name not in categories:
                    categories[cat_name] = {}
                
                # Deduplicação global de URLs
                if self.current_a_href not in seen_urls:
                    seen_urls.add(self.current_a_href)
                    categories[cat_name][self.current_a_href] = title
            self.in_a = False
            self.current_a_href = None
            self.current_a_title = ""
        elif tag == 'dl':
            if self.category_stack:
                self.category_stack.pop()

    def handle_data(self, data):
        if self.in_h3:
            self.current_h3_text += data
        elif self.in_a:
            self.current_a_title += data

# Leitura e parsing de cada arquivo de entrada
for filepath in input_files:
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        parser = BookmarkParser()
        parser.feed(content)
    except Exception as e:
        print(f"Aviso: Erro ao ler o arquivo {filepath}: {e}", file=sys.stderr)

# Escrita do arquivo HTML final compatível com navegadores
try:
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n")
        f.write("<!-- This is an automatically generated file. It will be read and overwritten. -->\n")
        f.write("<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n")
        f.write("<TITLE>Bookmarks</TITLE>\n")
        f.write("<H1>Bookmarks</H1>\n")
        f.write("<DL><p>\n")
        
        for cat_name, links in categories.items():
            if not links:
                continue
            f.write(f"    <DT><H3>{cat_name}</H3>\n")
            f.write("    <DL><p>\n")
            for url, title in links.items():
                f.write(f"        <DT><A HREF=\"{url}\">{title}</A>\n")
            f.write("    </DL><p>\n")
            
        f.write("</DL><p>\n")
    print(f"Sucesso! Arquivo mesclado salvo em: {output_file}")
except Exception as e:
    print(f"Erro ao escrever o arquivo de saída: {e}", file=sys.stderr)
    sys.exit(1)
EOF
