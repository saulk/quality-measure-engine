describe QME::Importer::PatientImporterCCR do

  before do
    @loader = reload_bundle
  end

  it "should import demographic information" do
    doc = Nokogiri::XML(File.new('fixtures/ccr_fragments/test1.xml'))
    patient = {}
    doc.root.add_namespace_definition('ccr','urn:astm-org:CCR')
    QME::Importer::PatientImporterCCR.instance.get_demographics(patient, doc)

    patient['first'].should == 'William'
    patient['last'].should == 'Test'
    patient['birthdate'].should == 432388800  # Time.iso8601("1983-09-14T12:00:00Z").to_i
    patient['gender'].should == 'male'
#    patient['patient_id'].should == '24602'
#   patient['race'].should == '2108-9'
#    patient['ethnicity'].should == '2137-8'
  end

  it 'should import a whole patient' do
    doc = Nokogiri::XML(File.new('fixtures/ccr_fragments/test1.xml'))
    doc.root.add_namespace_definition('ccr', 'urn:astm-org:CCR')

    measure_json = JSON.parse(File.read(File.join('fixtures', 'entry', 'sample.json')))
    QME::Importer::PatientImporterCCR.instance.add_measure('0043', QME::Importer::GenericImporter.new(measure_json))

    patient = QME::Importer::PatientImporterCCR.instance.parse(doc)

    patient['first'].should == 'William'
    binding.pry
    patient['measures']['0043']['encounter'].should include(1270598400)
  end

end