module QME
  module Importer

    # This class is the central location for taking an ASTM CCR XML document and converting it
    # into the processed form we store in MongoDB. The class does this by running each measure
    # independently on the XML document
    #
    # This class is a Singleton. It should be accessed by calling PatientImporter.instance
    class PatientImporterCCR

      include Singleton
 
      # Creates a new PatientImporter with the following XPath expressions used to find content in 
      # an ASTM CCR
      #
      # Encounter entries
      #    //ccr:Encounters/ccr:Encounter
      # Procedure entries
      #    //ccr:Procedures/ccr:Procedure
      #
      # Result entries - 
      #    //ccr:Results/ccr:Result
      #
      # Vital sign entries
      #    //ccr:VitalSigns/ccr:Result
      #
      # Medication entries
      #    //ccr:Medications/ccr:Medication
      #
      # Codes for medications are found in the Product sections
      #    ./ccr:Product
      #
      # Condition entries
      #    //ccr:Problems/ccr:Problem
      #
      # Social History entries 
      #    //ccr:SocialHistory/ccr:SocialHistoryElement
      #
      # Care Goal entries
      #    //ccr:Goals/ccr:Goal
      #
      # Allergy entries
      #    //ccr:Alerts/ccr:Alert
      #
      # Immunization entries
      #    //ccr:Immunizations/ccr:Immunization
      #
      # Codes for immunizations are found in the substanceAdministration with the following relative XPath
      #    ./ccr:Product
      
      def initialize (check_usable = true)
        @measure_importers = {}
        @section_importers = {}
        @section_importers[:encounters] = SectionImporterCCR.new("//ccr:Encounters/ccr:Encounter")
        @section_importers[:procedures] = SectionImporterCCR.new("//ccr:Procedures/ccr:Procedure")
        @section_importers[:results] = SectionImporterCCR.new("//ccr:Results/ccr:Result")
        @section_importers[:vital_signs] = SectionImporterCCR.new("//ccr:VitalSigns/ccr:Result")
        @section_importers[:medications] = SectionImporterCCR.new("//ccr:Medications/ccr:Medication", "./ccr:Product")
        @section_importers[:conditions] = SectionImporterCCR.new("//ccr:Problems/ccr:Problem")
        @section_importers[:social_history] = SectionImporterCCR.new("//ccr:SocialHistory/ccr:SocialHistoryElement")
        @section_importers[:care_goals] = SectionImporterCCR.new("//ccr:Goals/ccr:Goal")
        @section_importers[:medical_equipment] = SectionImporterCCR.new("//ccr:Equpment/ccr:EquipmentElement","./ccr:Product")
        @section_importers[:allergies] = SectionImporterCCR.new("//ccr:Alerts/ccr:Alert")
        @section_importers[:immunizations] = SectionImporterCCR.new("//ccr:Immunizations/ccr:Immunization","./ccr:Product" )
      end

 
      # @param [boolean] value for check_usable_entries...importer uses true, stats uses false 
      def check_usable(check_usable_entries)
        @section_importers.each_pair do |section, importer|
          importer.check_for_usable = check_usable_entries
        end
      end

      # Parses a ASTM CCR document and returns a Hash of of the patient.
      #
      # @param [Nokogiri::XML::Document] doc It is expected that the root node of this document
      #        will have the "cda" namespace registered to "urn:hl7-org:v3"
      # @return [Hash] a representation of the patient that can be inserted into MongoDB
      def parse(doc)
        ccr_patient = {}
        entries = create_ccr_hash(doc)
        get_demographics(ccr_patient, doc)
        process_events(ccr_patient, entries)
      end

      # Parses a patient hash containing demographic and event information
      #
      # @param [Hash] patient_hash patient data
      # @return [Hash] a representation of the patient that can be inserted into MongoDB
      def parse_hash(patient_hash)
        patient_record = {}
        patient_record['first'] = patient_hash['first']
        patient_record['patient_id'] = patient_hash['patient_id']
        patient_record['last'] = patient_hash['last']
        patient_record['gender'] = patient_hash['gender']
        patient_record['patient_id'] = patient_hash['patient_id']
        patient_record['birthdate'] = patient_hash['birthdate']
        patient_record['race'] = patient_hash['race']
        patient_record['ethnicity'] = patient_hash['ethnicity']
        patient_record['languages'] = patient_hash['languages']
        patient_record['addresses'] = patient_hash['addresses']
        event_hash = {}
        patient_hash['events'].each do |key, value|
          event_hash[key.intern] = parse_events(value)
        end
        process_events(patient_record, event_hash)
      end

      # Adds the entries and denormalized measure information to the patient_record.
      # Each Entry will be converted to a Hash and stored in an Array under the appropriate
      # section key, such as medications. Measure information is listed under the measures
      # key which has a Hash value. The Hash has the measure id as a key, and the denormalized
      # measure information as a value
      #
      # @param patient_record - Hash with basic patient demographic information
      # @entries - Hash of entries with section names a keys and an Array of Entry values
      def process_events(patient_record, entries)
        patient_record['measures'] = {}
        @measure_importers.each_pair do |measure_id, importer|
          patient_record['measures'][measure_id] = importer.parse(entries)
        end

        entries.each_pair do |key, value|
          patient_record[key] = value.map do |e|
            if e.usable?
              e.to_hash
            else
              nil
            end
          end.compact
        end

        patient_record
      end

      # Parses a list of event hashes into an array of Entry objects
      #
      # @param [Array] event_list list of event hashes
      # @return [Array] array of Entry objects
      def parse_events(event_list)
        event_list.collect do |event|
          if event.class==String.class
            # skip String elements in the event list, patient randomization templates
            # introduce String elements to simplify tailing-comma handling when generating
            # JSON using ERb
            nil
          else
            QME::Importer::Entry.from_event_hash(event)
          end
        end.compact
      end

      # Adds a measure to run on a CCR that is passed in
      #
      # @param [MeasureBase] measure an Class that can extract information from a CCR that is necessary
      #        to calculate the measure
      def add_measure(measure_id, importer)
        @measure_importers[measure_id] = importer
      end

      # Create a simple representation of the patient from an ASTM CCR
      #
      # @param [Nokogiri::XML::Document] doc It is expected that the root node of this document
      #        will have the "cda" namespace registered to "urn:hl7-org:v3"
      # @return [Hash] a represnetation of the patient with symbols as keys for each section
      def create_hash(doc, check_usable_entries = true)
        ccr_patient = {}
        @section_importers.each_pair do |section, importer|
          importer.check_for_usable = check_usable_entries
          ccr_patient[section] = importer.create_entries(doc,id_map)
        end
        c32_patient
      end

      # Inspects a CCR document and populates the patient Hash with first name, last name
      # birth date and gender.
      #
      # @param [Hash] patient A hash that is used to represent the patient
      # @param [Nokogiri::XML::Node] doc The CCR document parsed by Nokogiri
      def get_demographics(patient, doc)
        patientID = doc.at_xpath('/ccr:ContinuityOfCareRecord/ccr:Patient/ccr:Patient/ccr:ActorID').content
        patientActor = doc.at_xpath("/ccr:ContinuityOfCareRecord/ccr:Actors/ccr:Actor/[ccr:ActorObjectID = #{patientID}]")
        patient['first'] = patientActor.at_xpath('./ccr:Person/ccr:Name/ccr:CurrentName/ccr:Given').content
        patient['last'] = patientActor.at_xpath('./ccr:Person/ccr:Name/ccr:CurrentName/ccr:Family').content
        birthdate = patientActor.at_xpath('./ccr:DateOfBirth/ccr:ExactDateTime | ./ccr:DateOfBirth/ccr:ApproximateDateTime')
        patient['birthdate'] = Time.iso8601(birthdate).content)
        patient['gender'] = patientActor.at_Xpath('./Gender').content.downcase
        #race_node = doc.at_xpath('/ccr:placeholder')    #how do you find this?
        patient['race'] = nil
        #ethnicity_node = doc.at_xpath()
        patient['ethnicity'] = nil

        # languages = doc.at_xpath()
        patient['languages'] = nil
 
        patient['patient_id'] = patientID
      end
    end
  end
end
