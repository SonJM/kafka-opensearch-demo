package kr.co.weeds.kafkademo.config;

import org.apache.http.HttpHost;
import org.opensearch.client.RestClient;
import org.opensearch.client.RestHighLevelClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.net.URI;
import java.util.Arrays;

@Configuration
public class OpenSearchConfig {

    @Value("${opensearch.uris}")
    private String uris;

    @Bean
    public RestHighLevelClient openSearchClient() {
        // uris: "http://host1:9200, http://host2:9200"
        HttpHost[] hosts = Arrays.stream(uris.split(","))
                .map(String::trim)
                .map(URI::create)
                .map(uri -> new HttpHost(uri.getHost(), uri.getPort(), uri.getScheme()))
                .toArray(HttpHost[]::new);

        return new RestHighLevelClient(RestClient.builder(hosts));
    }
}
