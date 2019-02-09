(defun count-words-example (beggining end)
  "Count number of words in region."
  (interactive "r")
  (let ((count 0)
	(ready ()))
    (save-excursion
      (goto-char beggining)
      (while (and (< (point) end) (not ready))
	(if (not (re-search-forward "\\w+\\W*" end t))
	    (setq ready t)
	  (setq count (1+ count))))
      (cond ((zerop count)
	     (message "The region does NOT have words."))
	    ((= count 1)
	     (message "The region has 1 word."))
	    ((> count 1)
	     (message "The region has %d words." count))))))

(defun count-words-recur (beggining end)
  "Count number of words in region."
  (interactive "r")
  (save-excursion
    (goto-char beggining)
    (let ((count (count-words-recursion end)))
      (cond ((zerop count)
	     (message "The region does NOT have words."))
	    ((= count 1)
	     (message "The region has 1 word."))
	    ((> count 1)
	     (message "The region has %d words." count))))))

(defun count-words-recursion (end)
  (if (or (> (point) end)
	  (not (re-search-forward "\\w+\\W*" end t)))
      0
    (1+ (count-words-recursion end))))
  
 

(global-set-key "\C-c=" 'count-words-example)
