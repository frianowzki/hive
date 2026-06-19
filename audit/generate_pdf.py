#!/usr/bin/env python3
import markdown
from weasyprint import HTML

# Read markdown file
with open('audit/AUDIT_REPORT.md', 'r') as f:
    md_content = f.read()

# Convert markdown to HTML
html_content = markdown.markdown(md_content, extensions=['tables', 'fenced_code'])

# Add CSS styling
styled_html = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            margin: 40px;
            color: #333;
        }}
        h1 {{
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }}
        h2 {{
            color: #34495e;
            border-bottom: 2px solid #bdc3c7;
            padding-bottom: 8px;
            margin-top: 30px;
        }}
        h3 {{
            color: #7f8c8d;
            margin-top: 20px;
        }}
        table {{
            border-collapse: collapse;
            width: 100%;
            margin: 20px 0;
        }}
        th, td {{
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
        }}
        th {{
            background-color: #3498db;
            color: white;
        }}
        tr:nth-child(even) {{
            background-color: #f2f2f2;
        }}
        code {{
            background-color: #f4f4f4;
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
        }}
        pre {{
            background-color: #2c3e50;
            color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
        }}
        pre code {{
            background-color: transparent;
            color: #ecf0f1;
        }}
        strong {{
            color: #2c3e50;
        }}
        hr {{
            border: none;
            border-top: 2px solid #bdc3c7;
            margin: 30px 0;
        }}
        ul, ol {{
            margin: 10px 0;
            padding-left: 30px;
        }}
        li {{
            margin: 5px 0;
        }}
        .status-mitigated {{
            color: #27ae60;
            font-weight: bold;
        }}
        .status-acknowledged {{
            color: #f39c12;
            font-weight: bold;
        }}
        .severity-critical {{
            color: #e74c3c;
            font-weight: bold;
        }}
        .severity-high {{
            color: #e67e22;
            font-weight: bold;
        }}
        .severity-medium {{
            color: #f1c40f;
            font-weight: bold;
        }}
        .severity-low {{
            color: #3498db;
            font-weight: bold;
        }}
    </style>
</head>
<body>
{html_content}
</body>
</html>
"""

# Generate PDF
HTML(string=styled_html).write_pdf('audit/AUDIT_REPORT.pdf')

print("PDF generated: audit/AUDIT_REPORT.pdf")
