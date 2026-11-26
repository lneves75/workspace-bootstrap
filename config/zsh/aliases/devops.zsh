# Aliases for the optional CLI tools, defined only when the tool is installed.
# (The Oh My Zsh kubectl and terraform plugins define these too; they are
# repeated here so they exist even if those plugins are disabled.)

(( $+commands[kubectl] ))   && alias k='kubectl'
(( $+commands[terraform] )) && alias tf='terraform'
