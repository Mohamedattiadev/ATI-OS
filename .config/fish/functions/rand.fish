function rand
    if test (count $argv) -ne 1
        echo "Usage: rand <number_of_digits>"
        return 1
    end

    set digits $argv[1]
    if not string match -rq '^[0-9]+$' -- $digits
        echo "Please enter a valid number"
        return 1
    end

    set min (math "10 ^ ($digits - 1)")
    set max (math "(10 ^ $digits) - 1")

    set range (math "$max - $min + 1")
    set r (random)
    set rand_num (math "$min + ($r % $range)")

    echo $rand_num | xclip -selection clipboard # ✅ copies to clipboard
    echo $rand_num
end
