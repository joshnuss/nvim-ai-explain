" Extend Neovim's Markdown syntax in the read-only explanation buffer.
runtime! syntax/markdown.vim

syntax region AIExplainHeading matchgroup=Conceal start=/^ \{0,3}#\{1,6}\s\+/ end=/$/ oneline keepend concealends contains=@markdownInline
syntax match AIExplainListIndent /^ \{1,3}\ze[-*+]\s\+\S/ nextgroup=AIExplainBullet
syntax match AIExplainBullet /[-*+]\ze\s\+\S/ contained conceal cchar=•
syntax match AIExplainBullet /^[-*+]\ze\s\+\S/ conceal cchar=•
syntax region AIExplainInlineCode matchgroup=Conceal start=/\z(`\+\)/ end=/\z1\ze[^`]\|\z1$/ oneline concealends
syntax cluster markdownInline add=AIExplainInlineCode

" Keep punctuation and indentation literal inside fenced examples. A closing
" fence can be longer than the opening one, including in nested examples.
syntax region AIExplainCodeBlock matchgroup=Conceal start=/^\s*\z(`\{3,}\).*$/ end=/^\s*\z1`*\s*$/ keepend concealends
syntax region AIExplainCodeBlock matchgroup=Conceal start=/^\s*\z(\~\{3,}\).*$/ end=/^\s*\z1\~*\s*$/ keepend concealends
syntax sync fromstart

highlight default link AIExplainHeading Title
highlight default link AIExplainInlineCode Special
highlight default link AIExplainCodeBlock String
