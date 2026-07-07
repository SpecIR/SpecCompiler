-- Test oracle for VC-INT-016: Label Slugify Transliteration
-- slugify must transliterate accented Latin characters to ASCII base letters
-- so labels stay readable ("metodo-de-verificacao", not "mtodo-de-verificao").
-- Non-Latin scripts are still stripped; plain-ASCII behavior is unchanged.

return function(_, _)
    local label_utils = require("pipeline.shared.label_utils")

    local errors = {}
    local function check(got, expected, input)
        if got ~= expected then
            table.insert(errors, string.format(
                "slugify(%q) = %q, expected %q", input, tostring(got), expected))
        end
    end

    local cases = {
        -- Portuguese accents (the dissertation use case)
        { "Validação", "validacao" },
        { "Método de Verificação", "metodo-de-verificacao" },
        { "Definição do Artefato", "definicao-do-artefato" },
        { "Visão Geral da Solução", "visao-geral-da-solucao" },
        -- Uppercase accented letters must also transliterate + lowercase
        { "SEÇÃO Única", "secao-unica" },
        { "À Espera", "a-espera" },
        -- Other common Latin accents/ligatures
        { "Résumé naïve", "resume-naive" },
        { "Straße", "strasse" },
        { "Cœur mañana", "coeur-manana" },
        -- Non-Latin scripts are stripped, not transliterated
        { "data 日本語 x", "data-x" },
        -- Plain ASCII behavior unchanged
        { "Do Something!", "do-something" },
        { "  spaced   out  ", "spaced-out" },
    }

    for _, case in ipairs(cases) do
        check(label_utils.slugify(case[1]), case[2], case[1])
    end

    -- End-to-end through label computation
    local label = label_utils.compute_object_label("SECTION", "Visão Geral")
    if label ~= "section:visao-geral" then
        table.insert(errors, string.format(
            "compute_object_label = %q, expected 'section:visao-geral'", tostring(label)))
    end

    if #errors > 0 then
        return false, "Slugify transliteration failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    return true
end
