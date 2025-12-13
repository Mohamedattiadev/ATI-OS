function resumemode
    echo "🟢 Resuming all paused processes..."

    # resume all STOPped processes
    for pid in (ps -eo pid,stat | awk '$2 ~ /^T/ {print $1}')
        echo "Resuming PID $pid"
        kill -CONT $pid
    end

    # resume Docker containers
    if type -q docker
        set paused (docker ps -q --filter "status=paused")
        if test (count $paused) -gt 0
            echo "Unpausing Docker containers..."
            docker unpause $paused
        end
    end

    echo "✅ All processes resumed."
end
