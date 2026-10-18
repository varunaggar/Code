"""Download Edexcel IGCSE Maths papers and mark schemes from MathsGenie."""

import argparse
import json
import re
import ssl
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

import certifi


PAGE_URL = "https://mathsgenie.co.uk/igcse/maths/edexcel/papers"
RECORD_PATTERN = re.compile(
	r'"title":"(?P<title>(?:\\.|[^"\\])*)","board":"[^"]*",'
	r'"examYear":(?:\d+|null),"session":"[^"]*","paperLabel":"(?:\\.|[^"\\])*"'
	r'.*?"paperUrl":"(?P<paper_url>(?:\\.|[^"\\])*)",'
	r'"markSchemeUrl":(?:"(?P<mark_scheme_url>(?:\\.|[^"\\])*)"|null)',
	re.DOTALL,
)
USER_AGENT = "Mozilla/5.0 (compatible; MathsGeniePastPaperDownloader/1.0)"
TLS_CONTEXT = ssl.create_default_context(cafile=certifi.where())


def fetch_text(url):
	request = Request(url, headers={"User-Agent": USER_AGENT})
	with urlopen(request, timeout=30, context=TLS_CONTEXT) as response:
		return response.read().decode("utf-8", errors="replace")


def find_documents(page_html):
	documents = []
	seen_urls = set()
	serialized_data = page_html.replace(r'\"', '"')

	for match in RECORD_PATTERN.finditer(serialized_data):
		title = json.loads(f'"{match.group("title")}"')
		for kind, raw_url in (
			("paper", match.group("paper_url")),
			("mark_scheme", match.group("mark_scheme_url")),
		):
			if raw_url is None:
				continue
			url = json.loads(f'"{raw_url}"')
			parsed_url = urlsplit(url)
			if parsed_url.scheme != "https" or not parsed_url.path.lower().endswith(".pdf"):
				continue
			if url not in seen_urls:
				documents.append((kind, url, title))
				seen_urls.add(url)

	return documents


def make_filename(kind, title, url):
	if "predicted-current-2026" in url:
		tier = "Foundation" if "-foundation/" in url else "Higher"
		title = f"Predicted 2026 - {title} {tier}"
	title = re.sub(r"[\\/]", "", title)
	title = re.sub(r'[<>:"|?*]', "", title)
	title = re.sub(r"\s+", " ", title).strip().rstrip(".")
	document_type = "Question paper" if kind == "paper" else "Mark scheme"
	return f"{title} {document_type}.pdf"


def download_document(url, destination, overwrite):
	if destination.exists() and not overwrite:
		print(f"[skip] {destination.name} (already exists)")
		return True

	request = Request(url, headers={"User-Agent": USER_AGENT, "Referer": PAGE_URL})
	temporary_path = destination.with_suffix(destination.suffix + ".part")
	try:
		with urlopen(request, timeout=60, context=TLS_CONTEXT) as response:
			content = response.read()
		if not content.startswith(b"%PDF-"):
			raise ValueError("response did not contain a PDF")
		temporary_path.write_bytes(content)
		temporary_path.replace(destination)
		print(f"[saved] {destination}")
		return True
	except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
		temporary_path.unlink(missing_ok=True)
		print(f"[failed] {url}: {error}", file=sys.stderr)
		return False


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument(
		"--output",
		type=Path,
		default=Path.home() / "Documents" / "Avi Exams" / "Papers" / "Maths",
		help="directory for downloaded PDFs",
	)
	parser.add_argument(
		"--overwrite",
		action="store_true",
		help="replace files that have already been downloaded",
	)
	parser.add_argument(
		"--list-only",
		action="store_true",
		help="show how many PDF links were found without downloading them",
	)
	args = parser.parse_args()
	args.output = args.output.expanduser().resolve()

	try:
		documents = find_documents(fetch_text(PAGE_URL))
	except (HTTPError, URLError, TimeoutError, OSError) as error:
		print(f"Could not read the MathsGenie papers page: {error}", file=sys.stderr)
		return 1

	if not documents:
		print("No PDF links found; the page structure may have changed.", file=sys.stderr)
		return 1

	print(f"Found {len(documents)} PDFs (papers and mark schemes).")
	print(f"Output directory: {args.output}")
	filenames = [make_filename(kind, title, url) for kind, url, title in documents]
	if len(set(filenames)) != len(filenames):
		print("Duplicate output filenames detected; refusing to overwrite files.", file=sys.stderr)
		return 1
	if args.list_only:
		for filename in filenames[:8]:
			print(f"  {filename}")
		return 0

	args.output.mkdir(parents=True, exist_ok=True)
	failures = 0
	for kind, url, title in documents:
		filename = make_filename(kind, title, url)
		if not download_document(url, args.output / filename, args.overwrite):
			failures += 1

	print(f"Finished: {len(documents) - failures} succeeded, {failures} failed.")
	return 1 if failures else 0


if __name__ == "__main__":
	raise SystemExit(main())
