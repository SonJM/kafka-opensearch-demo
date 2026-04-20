package kr.co.weeds.kafkademo;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "Test Log", description = "topic-a로 테스트 로그 메시지를 전송하는 API")
@RestController
@RequiredArgsConstructor
public class TestLogController {

    private final KafkaTemplate<String, String> kafkaTemplate;

    @Operation(
            summary = "테스트 로그 전송",
            description = "입력한 메시지를 Kafka topic-a로 produce합니다."
    )
    @ApiResponse(responseCode = "200", description = "메시지 전송 성공")
    @PostMapping("/api/test/produce")
    public String produceLog(
            @Parameter(description = "topic-a로 전송할 메시지", example = "테스트로그")
            @RequestParam String message) {
        kafkaTemplate.send("topic-a", message);
        return "Sent to topic-a: " + message;
    }
}