#!/bin/bash

# ==============================================================================
# Script para mesclar e limpar arquivos de favoritos (.html) com contador
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
        while IFS= read -r -d '' file; do
            INPUT_FILES+=("$file")
        done < <(find "$arg" -type f \( -iname "*.html" -o -iname "*.htm" \) -print0)
    elif [ -f "$arg" ]; then
        INPUT_FILES+=("$arg")
    else
        echo "Aviso: Caminho ignorado (não é um arquivo nem diretório válido): $arg" >&2
    fi
done

if [ "${#INPUT_FILES[@]}" -eq 0 ]; then
    echo "Erro: Nenhum arquivo .html válido foi encontrado nos caminhos fornecidos." >&2
    exit 1
fi

echo "Processando ${#INPUT_FILES[@]} arquivo(s) encontrado(s)..."
echo ""

# 4. Bloco Python embutido para parsing, contagem individual/global e geração do HTML
python3 - "$OUTPUT_FILE" "${INPUT_FILES[@]}" << 'EOF'
import sys
import os
import html
from html.parser import HTMLParser

# Evita UnicodeEncodeError ao imprimir nomes de arquivos em locales não-UTF-8
try:
    sys.stdout.reconfigure(errors='replace')
    sys.stderr.reconfigure(errors='replace')
except AttributeError:
    pass

output_file = sys.argv[1]
input_files = sys.argv[2:]
output_real = os.path.realpath(output_file)

# Nome da pasta para favoritos que não estão dentro de nenhuma pasta
LOOSE_FOLDER_NAME = "Outros"

# Pastas raiz dos navegadores que NÃO devem aparecer na hierarquia.
# (Além disso, qualquer <H3> com PERSONAL_TOOLBAR_FOLDER="true" é ignorado.)
ROOT_FOLDER_NAMES = {
    "bookmarks toolbar",
    "bookmarks bar",
    "barra de favoritos",
    "barra de marcadores",
    "barra de ferramentas de favoritos",
}

# Árvore global de pastas: cada nó = {"links": {url: titulo}, "children": {nome: nó}}
def new_node():
    return {"links": {}, "children": {}}

root = new_node()
seen_urls = set()


def get_node(path):
    """Retorna (criando se necessário) o nó da árvore para o caminho dado."""
    node = root
    for name in path:
        node = node["children"].setdefault(name, new_node())
    return node


class BookmarkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        # Cada <DL> empilha exatamente uma entrada (nome da pasta ou None),
        # e cada </DL> desempilha exatamente uma, mantendo a pilha balanceada.
        self.dl_stack = []
        self.pending_folder = None   # nome do <H3> aguardando o próximo <DL>
        self.in_h3 = False
        self.h3_text = ""
        self.h3_is_root = False      # <H3> é a pasta da barra de favoritos?
        self.in_a = False
        self.a_href = None
        self.a_title = ""
        self.entries = {}            # {caminho (tupla): {url: titulo}}
        self.file_seen_urls = set()

    def handle_starttag(self, tag, attrs):
        # HTMLParser já converte os nomes das tags e atributos para minúsculas
        attrs_dict = dict(attrs)
        if tag == 'dt':
            # Novo item: descarta nome de pasta pendente que não recebeu <DL>
            self.pending_folder = None
        elif tag == 'h3':
            self.in_h3 = True
            self.h3_text = ""
            self.pending_folder = None
            self.h3_is_root = (
                (attrs_dict.get('personal_toolbar_folder') or "").lower() == "true"
            )
        elif tag == 'a':
            href = attrs_dict.get('href')
            if href and href.strip():
                self.in_a = True
                self.a_href = href.strip()
                self.a_title = ""
        elif tag == 'dl':
            self.dl_stack.append(self.pending_folder)
            self.pending_folder = None

    def handle_endtag(self, tag):
        if tag == 'h3':
            self.in_h3 = False
            name = self.h3_text.strip()
            # Pasta raiz da barra de favoritos: não entra na hierarquia
            if self.h3_is_root or name.casefold() in ROOT_FOLDER_NAMES:
                name = ""
            self.pending_folder = name or None
            self.h3_is_root = False
        elif tag == 'a':
            if self.in_a and self.a_href:
                # Deduplicação interna por arquivo para o contador individual
                if self.a_href not in self.file_seen_urls:
                    self.file_seen_urls.add(self.a_href)
                    path = tuple(name for name in self.dl_stack if name)
                    title = self.a_title.strip() or self.a_href
                    self.entries.setdefault(path, {})[self.a_href] = title
            self.in_a = False
            self.a_href = None
            self.a_title = ""
        elif tag == 'dl':
            if self.dl_stack:
                self.dl_stack.pop()

    def handle_data(self, data):
        if self.in_h3:
            self.h3_text += data
        elif self.in_a:
            self.a_title += data


# Leitura, contagem individual e parsing de cada arquivo de entrada
processed = set()
for filepath in input_files:
    real = os.path.realpath(filepath)

    if real == output_real:
        print(f"  [Ignorado] {filepath}: é o próprio arquivo de saída.")
        continue
    if real in processed:
        print(f"  [Ignorado] {filepath}: já processado (caminho repetido).")
        continue
    processed.add(real)

    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        parser = BookmarkParser()
        parser.feed(content)
        parser.close()

        # Exibe a contagem de favoritos únicos do arquivo alimentado
        file_unique_count = len(parser.file_seen_urls)
        print(f"  [Entrada] {filepath}: {file_unique_count} favoritos únicos encontrados.")

        # Mesclagem global e deduplicação entre arquivos
        for path, links in parser.entries.items():
            target_path = path if path else (LOOSE_FOLDER_NAME,)
            for url, title in links.items():
                if url not in seen_urls:
                    seen_urls.add(url)
                    get_node(target_path)["links"][url] = title

    except Exception as e:
        print(f"Aviso: Erro ao ler o arquivo {filepath}: {e}", file=sys.stderr)

total_unique_final = len(seen_urls)
print(f"\n  [Saída] Total consolidado de favoritos únicos no arquivo final: {total_unique_final}\n")


def write_links(f, node, pad):
    for url, title in node["links"].items():
        escaped_url = html.escape(url, quote=True)
        escaped_title = html.escape(title)
        f.write(f"{pad}<DT><A HREF=\"{escaped_url}\">{escaped_title}</A>\n")


def write_folder(f, name, node, depth):
    """Escreve uma pasta e, recursivamente, suas subpastas."""
    pad = "    " * depth
    f.write(f"{pad}<DT><H3>{html.escape(name)}</H3>\n")
    f.write(f"{pad}<DL><p>\n")
    write_links(f, node, pad + "    ")
    for child_name, child in node["children"].items():
        write_folder(f, child_name, child, depth + 1)
    f.write(f"{pad}</DL><p>\n")


# Escrita do arquivo HTML final compatível com navegadores (com escape de caracteres)
try:
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n")
        f.write("<!-- This is an automatically generated file. It will be read and overwritten. -->\n")
        f.write("<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n")
        f.write("<TITLE>Bookmarks</TITLE>\n")
        f.write("<H1>Bookmarks</H1>\n")
        f.write(f"<!-- Total Unique Bookmarks Count: {total_unique_final} -->\n")
        f.write("<DL><p>\n")

        write_links(f, root, "    ")
        for name, child in root["children"].items():
            write_folder(f, name, child, 1)

        f.write("</DL><p>\n")
    print(f"Sucesso! Arquivo mesclado salvo em: {output_file}")
except Exception as e:
    print(f"Erro ao escrever o arquivo de saída: {e}", file=sys.stderr)
    sys.exit(1)
EOF
