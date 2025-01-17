"
Functions that relate to output on the screen.
"

(require hyrule.argmove [-> ->> as->])
(require hyrule.control [case])

(import os)
(import re)
(import atexit)
(import readline)
(import hashlib [md5])

(import rich.console [Console])
(import rich.padding [Padding])
(import rich.markdown [Markdown])
(import rich.columns [Columns])
(import rich.table [Table])
(import rich.text [Text])
(import rich.progress [track])
(import rich.color [ANSI_COLOR_NAMES])

; not sure if this is worth it.
;(import prompt-toolkit [HTML prompt :as pprompt])

;; TODO: set up separate output and input consoles

;; -----------------------------------------------------------------------------

(setv console (Console :highlight None))
(setv colors (list (.keys ANSI_COLOR_NAMES)))
(setv render-markdown True)

;; status bar
(setv toolbar "")

;; load/save readline history at startup/exit
;; -----------------------------------------------------------------------------

(try
  (let [history-file (os.path.join (os.path.expanduser "~") ".chasm_history")]
    (.register atexit readline.write-history-file history-file)
    (readline.set-history-length 100)
    (readline.read-history-file history-file))
  (except [e [FileNotFoundError]]))

;; Input, status
;; -----------------------------------------------------------------------------

(defn rlinput [prompt [prefill ""]]
  "Like python's input() but using readline."
  (clear-status-line)
  (display-status-line)
  (readline.set_startup_hook (fn [] (readline.insert_text prefill)))
  (try
    (input prompt)
    (except [EOFError]
      "/quit")
    (finally
      (readline.set_startup_hook))))

(defn display-status-line []
  "Print a status line at the bottom of the screen."
  ;(print "\033[s" :end "") ; save cursor position
  ;(print "\033[u" :end "") ; restore cursor position
  (print) ; move on one line
  (console.rule)
  ; s-without-markup (re.sub r"\[[/\w ]*\]" "" s)
  (console.print toolbar
                 :end "\r"
                 :overflow "ellipsis"
                 :crop True)
  (for [n (range (+ 2 (.count toolbar "\n")))]
    (print "\033[1A" :end "")) ; up one line
  (print "\033[K" :end "")) ; clear to end of line for new input

(defn set-window-title [s]
  (console.set-window-title s))

(defn set-status-line [s]
  "Set the status line."
  (global toolbar)
  (setv toolbar s))
  
(defn clear-status-line []
  "Hack to avoid old status line polluting new output."
  (print "\033[K" :end "") ; clear to end of line
  (print)
  (print "\033[K" :end "") ; clear to end of line
  (print)
  (print "\033[K" :end "") ; clear to end of line
  (print)
  (print "\033[1A" :end "") ; up one line
  (print "\033[1A" :end "") ; up one line
  (print "\033[1A" :end "")) ; up one line
  
(defn pinput [prompt]
  "Input with prompt-toolkit."
  (pprompt prompt :bottom-toolbar (HTML toolbar)))

(defn _bold [s]
  (+ "[bold]" s "[/bold]"))

(defn _italic [s]
  (+ "[italic]" s "[/italic]"))

(defn _color [s [color "black"]]
  (+ f"[{color}]" s f"[/{color}]"))

;; Screen control
;; -----------------------------------------------------------------------------

(defn clear []
  (console.clear))
  
(defn set-width [line]
  (try
    (let [arg (get (.partition line " ") 2)]
      (global console)
      (setv console (Console :highlight None :width (int arg))))
    (except [[IndexError ValueError]]
      (error f"Bad console width value: {arg}"))))

(defn toggle-markdown []
  "Toggle the rendering of markdown in output."
  (global render-markdown)
  (setv render-markdown (not render-markdown)))

(defn spinner [s [style "italic blue"] [spinner "dots12"]]
  (console.status (Text s :style style)
                  :spinner spinner))

;; Formatters
;; -----------------------------------------------------------------------------

(defn close-quotes [s]
  "If there is an odd number of quotes in a line, close the quote."
  (.join "\n"
    (lfor line (-> s (.replace "\"\"" "\"") (.splitlines))
          (if (% (.count line "\"") 2)  ; if an odd number of quotes
            (cond (= (cut line -2 None) " \"") (cut line 0 -2)
                  (= (get line -1) "\"")       f"\"{line}"            ; close at start
                  :else                        f"{line}\"")           ; close at end
            line))))

(defn sanitize-markdown [s]
  "Prepare a generic string for markdown rendering."
  ;; Markdown swallows single newlines.
  ;; and defines the antipattern of preserving them with a double space.
  ;; but we don't want to lose itemised lists
  (re.sub r"\n" r"  \n" (.strip s)))

(defn role-color [role]
  "The signature color of the role, derived from its name."
  (let [role (.capitalize role)
        i (-> (role.encode "utf-8")
              (md5)
              (.hexdigest)
              (int 16)
              (% 222)
              (+ 1))]
    (get colors i)))

;; Printers
;; -----------------------------------------------------------------------------

(defn info [s [style "blue italic"] [width 100]]
  "Print an information string to the screen."
  (print-message
    {"role" "system" "content" s}
    :style style
    :width width))

(defn error [s [style "red italic"] [width 100]]
  "Print an error string to the screen."
  (print-message
    {"role" "system" "content" s}
    :style style
    :width width))

(defn exception []
  "Formats and prints the current exception."
  (console.print-exception :max-frames 2))

;; -----------------------------------------------------------------------------

(defn banner []
  (console.clear)
  (setv banner-text r"       _:
   ___| |__   __ _ ___ _ __ ___ :
  / __| '_ \ / _` / __| '_ ` _ \ :
 | (__| | | | (_| \__ \ | | | | | :
  \___|_| |_|\__,_|___/_| |_| |_| :
 :")
  (lfor [l c] (zip (.split banner-text ":")
                   ["#11FF00" "#33DD00" "#33BB00" "#339900" "#337720" "#227799" "#2288FF" "#2288FF"])
        (console.print l
                       :end None
                       :style f"bold {c}"
                       :overflow "crop"))
  (console.print "[default]"))

(defn print-input [prompt [width 100] [prompt-width 2]]
  (let [margin (* " " (max 0 (- (// (- console.width width) 2) 10)))
        line (.strip (rlinput f"{margin}{prompt}"))]
    (print "\033[1A" :end "") ; up one line
    (print "\033[K" :end "") ; clear to end of line
    (when line
      (print-message {"role" "user" "content" f"*{line}*"
                      :width width
                      :prompt-width prompt-width}))
    line))
  
(defn print-messages [messages [width 100]]
  "Format and print messages to the terminal."
  (console.rule)
  (console.print)
  (for [msg messages]
    (print-message msg :width width :prompt-width 10))
  (console.rule))

(defn print-message [msg [width 100] [prompt-width 2] [style None]]
  "Format and print a message with role to the screen."
  (let [text (-> msg (:content) (close-quotes))
        color (role-color (:role msg))
        width (min width console.width)
        margin (max 0 (- (// (- console.width width) 2) 10))
        output (Table :width (+ margin width 2)
                      :padding #(0 0 1 0)
                      :show-header False
                      :show-lines False
                      :box None)
        role-prompt (case (:role msg)
                          "assistant" ""
                          "user" "  > "
                          "system" ""
                          else f"{(:role msg)}: ")]
    (.add-column output :width (- margin prompt-width))
    (.add-column output :min-width prompt-width)
    (.add-column output :width width :overflow "fold")
    (.add-row output "" f"[bold {color}]{role-prompt}[/bold {color}]"
              (if render-markdown
                  (Markdown (sanitize-markdown text))
                  text))
    (console.print output :justify "left" :style style)))

(defn print-last-message [messages] 
  (-> messages
    (get -1)
    (print-message))) 

(defn tabulate [rows headers
                [styles None]
                [title None]]
  "Print a rich table object from a list of lists (rows) and a list (headers)."
  (let [table (Table :title title :row-styles styles)]
    (for [h headers]
      (.add-column table h))
    (for [r rows]
      (.add-row table #* r))
    (console.print table :style "green")))
