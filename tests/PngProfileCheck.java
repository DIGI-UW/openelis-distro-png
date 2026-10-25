package org.itech.ahb.profile;

import com.fasterxml.jackson.databind.*;
import java.nio.file.*;
import java.time.Clock;
import java.util.*;
import org.springframework.core.io.*;
import org.itech.ahb.fhir.*;
import org.itech.ahb.fhir.FhirBundleBuilder.*;

/** Synthetic contract checks against the released Bridge, not physical instrument certification. */
public class PngProfileCheck {
  static final ObjectMapper JSON = new ObjectMapper();
  static void require(boolean ok, String message) {
    if (!ok) throw new AssertionError(message);
  }
  static String message(String sample, String code, String value, boolean qc, boolean gene) {
    String[] order = new String[17];
    Arrays.fill(order, "");
    order[0]="O"; order[1]="1"; order[2]=sample; order[11]=qc?"Q":"";
    order[15]=qc?"Bts":"";
    return "H|\\^&|||PNG-SYNTHETIC\rP|1\r" + String.join("|", order)
      + "\rR|1|^^^" + code + (gene?"^reported":"") + "|" + value + "||\rL|1|N\r";
  }
  static JsonNode check(JsonNode profile, String code, String value, boolean qc, boolean failed) throws Exception {
    String id=profile.path("profileMeta").path("id").asText();
    boolean gene=id.contains("genexpert");
    var recognition=ControlResultRecognition.fromProfile(profile.path("controlResultRecognition"));
    var reading=ResultReading.fromProfile(profile);
    var parsed=ASTMResultParser.parseRaw(message("PNG-SYNTHETIC-001",code,value,qc,gene),recognition,
      AstmResultRecordSelection.fromProfile(profile.path("configDefaults")),reading);
    require(parsed!=null && parsed.results().size()==1,id+": expected one selected result");
    var result=parsed.results().get(0);
    require(result.testCode().equals(code),id+": preserve analyzer-native code");
    require(result.isControl()==qc,id+": control classification");
    require(result.parts().runFailed()==failed,id+": failed-run classification");
    var context=new AnalyzerContext("png-synthetic-connection","png-synthetic-analyzer",id,1,"ASTM","TCP/IP",
      DeviceInfo.fromSenderToken("png-synthetic","PNG-SYNTHETIC"),recognition,profile.path("catalog").path("recognitionFingerprint").asText(),profile.path("catalog").path("revisionFingerprint").asText(),reading);
    var bundle=JSON.readTree(FhirBundleBuilder.buildNormalizedBundle(parsed,context,c -> null,"png-synthetic-delivery"));
    require(bundle.path("identifier").path("value").asText().equals("png-synthetic-delivery"),"delivery identity");
    JsonNode observation=null;
    for(var entry:bundle.path("entry")) if(entry.path("resource").path("resourceType").asText().equals("Observation")) observation=entry.path("resource");
    require(observation!=null,id+": normalized observation");
    require(observation.has("dataAbsentReason")==failed,id+": failed run must be explicit in FHIR");
    System.out.println("PASS "+id+" "+code+" value="+value+" control="+qc+" failed="+failed);
    return observation;
  }
  public static void main(String[] args) throws Exception {
    Path root=Path.of(args[0]), state=Path.of(args[1]);
    List<Resource> resources=new ArrayList<>();
    try(var files=Files.walk(root)) { files.filter(p->p.toString().endsWith(".json")).sorted().forEach(p->resources.add(new FileSystemResource(p))); }
    var catalog=new AnalyzerProfileCatalog(state,resources,JSON,Clock.systemUTC());
    require(catalog.issues().isEmpty(),"Catalog rejected profiles: "+catalog.issues());
    require(catalog.latest().size()==3,"Only the three PNG types should be shipped");
    for(var revision:catalog.latest()) {
      var p=revision.profile();
      var id=p.path("profileMeta").path("id").asText();
      require(!p.path("capabilities").path("outboundOrders").asBoolean(),"PNG results-only scope");
      if(id.contains("genexpert")) {
        var normal=check(p,"HIV-1_VL 2","1250",false,false);
        require(normal.has("valueString"),"PNG HIVVL catalog is textual: preserve reported value");
        check(p,"MTB-RIF_ULTRA 2","ERROR",false,true);
        check(p,"HIV-1_QUAL 2 2","NEGATIVE",true,false);
      } else if(id.contains("epicenter")) {
        var normal=check(p,"MGIT_960_GND","NEGATIVE",false,false);
        require(normal.has("valueCodeableConcept"),"Culture result must carry a coded answer");
        check(p,"PLUSAEF","NEGATIVE",true,false);
      } else {
        check(p,"ORGANISM","Escherichia coli",false,false);
        check(p,"ORGANISM","No reliable identification",false,true);
        check(p,"ORGANISM","Escherichia coli",true,false);
        var score=check(p,"SCORE","2.31",false,false);
        require(score.path("valueString").asText().equals("2.31"),"Unconfigured SCORE must remain visible as raw text");
        require(score.path("code").path("coding").size()==1,"SCORE must not advertise organism-identification LOINC");
      }
    }
    System.out.println("PASS: three shipped profiles and nine normalized result cases using released Bridge code.");
  }
}
