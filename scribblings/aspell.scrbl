#lang scribble/manual
@require[@for-label[aspell
                    racket/base]]

@title{Interface to GNU Aspell}
@author[@author+email["Shawn Wagner" "shawnw.mobile@gmail.com"]]

@defmodule[aspell]

Provides an interface to @hyperlink["http://aspell.net/"]{GNU ASpell} for spell-checking text from your programs. The @tt{aspell} program must be present in your path to use this module.

@section{Controlling aspell}

@defproc[(aspell? [obj any/c]) boolean?]{

 Test if a value is an aspell instance.

}

@defproc[(open-aspell [#:dict dict (or/c string? #f) #f]
                      [#:personal-dict personal-dict (or/c path-string? #f) #f]
                      [#:dict-dir dict-dir (or/c path-string? #f) #f]
                      [#:lang lang (or/c string? #f) #f]
                      [#:mode mode symbol? 'url]
                      [#:ignore-case ignore-case boolean? #f]) aspell?]{

 Start a new aspell instance. If any of the options are false, values are chosen by aspell from its defaults and the current locale. Generally this is the desired behavior.
 See its documentation for details.

 @tt{aspell dump modes} will give the possible values for the @code{#:mode} option.

 }

@defproc[(close-aspell [speller aspell?]) void?]{

 Close a running aspell instance. It should not be used after calling this function.

}

@section{Spell checking}

@defproc[(aspell-check [speller aspell?] [text string?]) list?]{

 Spell check the given @code{text} and return a list of misspelled words. Each element of the list is itself a list. The first element is the misspelled word, the second is its position from the start of the line it's in (@bold{Not} the start of the string if there are multiple lines), and any remaining elements are suggested correct words, if any.

 Care must be taken that any single line isn't larger than your system's pipe buffer space.
                       
}

@section{Dictionaries}

In addition to the master dictionary, aspell supports personal dictionaries and a temporary session dictionary of accepted words. The personal dictionary can include suggested replacment words for given misspellings, or just words to accept as correctly spelled.

@defproc[(aspell-add-word [speller aspell?] [word string?] [dict (or/c string? 'personal 'session) 'session]) void?]{

 Add a new word to the given dictionary, or add a misspelled word and suggested replacement to the personal dictionary.

}

@defproc[(aspell-get-dictionary [speller aspell?] [dict (or/c 'personal 'session)]) (listof string?)]{

 Return a list of the words in the given dictionary.

}

@defproc[(aspell-save-dictionary [speller aspell?]) void?]{

 Save the personal dictionary.

}

@section{Other functions}

@defproc[(aspell-active? [speller aspell?]) boolean?]{

 Returns true if the aspell instance is active, false if it's been closed.

}

@defproc[(aspell-language [speller aspell?]) string?]{

 Return the language being used for spell checking.

 }