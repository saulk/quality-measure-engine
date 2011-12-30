describe QME::Importer::PatientImporterC32 do

  before do
    @loader = reload_bundle
  end

  it "should import demographic information" do
    doc = Nokogiri::XML(File.new('fixtures/c32_fragments/demographics.xml'))
    patient = {}
    doc.root.add_namespace_definition('cda', 'urn:hl7-org:v3')
    QME::Importer::PatientImporterC32.instance.get_demographics(patient, doc)

    patient['first'].should == 'Joe'
    patient['last'].should == 'Smith'
    patient['birthdate'].should == -87696000
    patient['gender'].should == 'M'
    patient['patient_id'].should == '24602'
    patient['race'].should == '2108-9'
    patient['ethnicity'].should == '2137-8'
  end

  it 'should import a whole patient' do
    doc = Nokogiri::XML(File.new('fixtures/c32_fragments/0032/numerator.xml'))
    doc.root.add_namespace_definition('cda', 'urn:hl7-org:v3')

    measure_json = JSON.parse(File.read(File.join('fixtures', 'entry', 'sample.json')))
    QME::Importer::PatientImporterC32.instance.add_measure('0043', QME::Importer::GenericImporter.new(measure_json))

    patient = QME::Importer::PatientImporterC32.instance.parse(doc)

    patient['first'].should == 'FirstName'
    patient['measures']['0043']['encounter'].should include(1270598400)
  end

end