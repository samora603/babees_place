/**
 * Admin data export helpers (CSV / JSON / Excel-friendly CSV / printable PDF).
 * No heavy dependencies — Excel opens UTF-8 BOM CSV; PDF uses print window.
 */

import { auditService, AUDIT_ACTIONS } from '@/services/auditService';

function downloadBlob(filename, blob) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function escapeCsv(value) {
  const s = value == null ? '' : String(value);
  if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

/**
 * @param {Array<object>} rows
 * @param {string[]} [columns]
 */
export function toCsv(rows, columns) {
  if (!rows?.length) return '';
  const cols = columns || Object.keys(rows[0]);
  const header = cols.map(escapeCsv).join(',');
  const body = rows.map((row) => cols.map((c) => escapeCsv(row[c])).join(',')).join('\n');
  return `${header}\n${body}`;
}

export function exportCsv(filename, rows, columns) {
  const csv = `\uFEFF${toCsv(rows, columns)}`;
  downloadBlob(filename.endsWith('.csv') ? filename : `${filename}.csv`, new Blob([csv], {
    type: 'text/csv;charset=utf-8',
  }));
}

/** Excel-friendly CSV (.xlsx extension avoided without a real workbook library). */
export function exportExcel(filename, rows, columns) {
  const base = filename.replace(/\.xlsx?$/i, '');
  exportCsv(`${base}.csv`, rows, columns);
}

export function exportJson(filename, data) {
  const name = filename.endsWith('.json') ? filename : `${filename}.json`;
  downloadBlob(name, new Blob([JSON.stringify(data, null, 2)], {
    type: 'application/json',
  }));
}

/**
 * Opens a print-friendly report window (Save as PDF from the browser).
 */
export function exportPdfReport({ title, subtitle = '', rows = [], columns }) {
  const cols = columns || (rows[0] ? Object.keys(rows[0]) : []);
  const tableRows = rows.map((row) => (
    `<tr>${cols.map((c) => `<td>${escapeHtml(row[c])}</td>`).join('')}</tr>`
  )).join('');
  const html = `<!DOCTYPE html><html><head><title>${escapeHtml(title)}</title>
    <style>
      body{font-family:system-ui,sans-serif;padding:24px;color:#111}
      h1{font-size:20px;margin:0 0 4px} p{color:#555;margin:0 0 16px}
      table{border-collapse:collapse;width:100%;font-size:12px}
      th,td{border:1px solid #ddd;padding:6px 8px;text-align:left}
      th{background:#f5f5f5}
    </style></head><body>
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(subtitle)} · Generated ${new Date().toLocaleString()}</p>
    <table><thead><tr>${cols.map((c) => `<th>${escapeHtml(c)}</th>`).join('')}</tr></thead>
    <tbody>${tableRows || '<tr><td colspan="99">No rows</td></tr>'}</tbody></table>
    <script>window.onload=()=>window.print()</script>
    </body></html>`;

  const w = window.open('', '_blank', 'noopener,noreferrer');
  if (!w) throw new Error('Popup blocked — allow popups to export PDF');
  w.document.write(html);
  w.document.close();
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export async function exportAndAudit(format, filename, rows, columns, entityType = 'report') {
  if (format === 'json') exportJson(filename, rows);
  else if (format === 'pdf') exportPdfReport({ title: filename, rows, columns });
  else if (format === 'excel') exportExcel(filename, rows, columns);
  else exportCsv(filename, rows, columns);

  await auditService.writeAuditSafe({
    action: AUDIT_ACTIONS.EXPORT_GENERATED,
    entityType,
    summary: `Exported ${format}: ${filename}`,
    metadata: { format, rowCount: rows?.length || 0 },
  });
}

export const exportService = {
  toCsv,
  exportCsv,
  exportExcel,
  exportJson,
  exportPdfReport,
  exportAndAudit,
};
