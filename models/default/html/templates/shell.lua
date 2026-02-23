---HTML document shell template.
---Generates the complete <!DOCTYPE html> wrapper with embedded CSS, JS, and content.
---@module models.default.html.templates.shell
local M = {}

---Render the complete HTML document.
---@param opts table Options: title, css, body_html, embedded_data, js
---@return string Complete HTML document
function M.render(opts)
    return table.concat({
        '<!DOCTYPE html>',
        '<html lang="en" data-theme="light">',
        '<head>',
        '  <meta charset="UTF-8">',
        '  <meta name="viewport" content="width=device-width, initial-scale=1.0">',
        '  <title>' .. (opts.title or 'Documentation') .. '</title>',
        '  <style>' .. (opts.css or '') .. '</style>',
        '</head>',
        '<body>',
        '  ' .. (opts.body_html or ''),
        '  ' .. (opts.embedded_data or ''),
        '  <script>' .. (opts.js or '') .. '</script>',
        '</body>',
        '</html>',
    }, '\n')
end

return M
