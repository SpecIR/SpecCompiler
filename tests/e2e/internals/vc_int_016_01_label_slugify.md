# spec: Label Slugify Transliteration @SPEC-INT-016

## section: UTF-8 Transliteration in Labels @VC-INT-016

Accented Latin characters in titles must transliterate to their ASCII base
letters (ç→c, á→a) so generated labels are readable and referenceable, instead
of dropping the bytes and mangling words (Validação → validao).

### Seção com Acentuação @REQ-INT-016-01

Esta seção existe para que o pipeline gere um label a partir de título
acentuado.
