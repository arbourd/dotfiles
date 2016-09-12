function docker-clean --description 'Clean up exited containers and dangling images for Docker'
    switch "$argv[1]"
        case containers
            __clean-containers
        case images
            __clean-images
        case '*'
            __clean-containers & __clean-images
    end

    function __clean-containers --description 'Remove exited Docker containers'
        docker ps -a -q --filter="status=exited" | xargs docker rm
    end

    function __clean-images --description 'Remove untagged Docker images'
        docker images --quiet --filter=dangling=true | xargs docker rmi
    end
end
